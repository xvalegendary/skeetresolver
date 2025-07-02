-- Resolver • v6.3 (optimized)
--  • single lookup table S (lightweight)      • endless MP3 loop via delay_call / paint
--  • no nil‑index errors                      • concise HUD + toggleable watermark
--  • all controls:  RAGE → Other
------------------------------------------------------------------------
local E,UI,P,R,C,G = entity, ui, plist, renderer, client, globals
local M            = { m=math, b=bit }
------------------------------------------------------------------------
-- ◇ UI ----------------------------------------------------------------
local cb_on  = UI.new_checkbox("RAGE","Other","Resolver: Enable")
local cb_mode= UI.new_combobox("RAGE","Other","Resolver Mode","Safe","Balanced","Learning","Brute","Aggressive","Novosibirsk")
UI.new_label("RAGE","Other","— Heuristics —")
local cb_head= UI.new_checkbox("RAGE","Other","Head trace check")
local cb_body= UI.new_checkbox("RAGE","Other","Body trace fallback")
local cb_lag = UI.new_checkbox("RAGE","Other","Lag‑peek filter")
local cb_step= UI.new_checkbox("RAGE","Other","Adaptive step")
local sl_step= UI.new_slider("RAGE","Other","Step size",5,30,15,"°")
local cb_side= UI.new_checkbox("RAGE","Other","Jitter side‑guess")
local sl_side= UI.new_slider("RAGE","Other","Side guess angle",30,90,58,"°")
local sl_brute= UI.new_slider("RAGE","Other","Brute spread",10,60,30,"°")
local sl_aggr = UI.new_slider("RAGE","Other","Aggressive spread",10,40,25,"°")
UI.new_label("RAGE","Other","— Visuals —")
local cp_col = UI.new_color_picker("RAGE","Other","Indicator colour",80,150,255,255)
local cb_wm  = UI.new_checkbox("RAGE","Other","Watermark")
local sl_wm_speed = UI.new_slider("RAGE","Other","Watermark speed",1,10,5,"x")
UI.new_label("RAGE","Other","— Audio —")
local cb_song= UI.new_checkbox("RAGE","Other","Play Новосибирская игра ♫")
------------------------------------------------------------------------
local SONG      = "novosibirskaia.mp3"  -- csgo/sound/
local SONG_LEN  = 120                   -- seconds
local has_delay = C.delay_call ~= nil
local next_song = 0
local function play_song() C.exec(('playvol "%s" 1'):format(SONG)) end
local function loop_song()
  play_song(); if has_delay then C.delay_call(SONG_LEN, loop_song) else next_song = G.curtime()+SONG_LEN end
end
C.set_event_callback("round_start", function() if UI.get(cb_song) then loop_song() end end)
if not has_delay then C.set_event_callback("paint", function() if next_song~=0 and G.curtime()>=next_song then loop_song() end end) end
------------------------------------------------------------------------
-- ◇ State ------------------------------------------------------------
local S={yaw={},sim={},cls={},idx={},last={},miss={}}; local last_log=0
------------------------------------------------------------------------
-- ◇ Helpers ----------------------------------------------------------
local function yaw(e)   return M.m.floor(((E.get_prop(e,"m_flPoseParameter",11) or 0)*120)-60+0.5) end
local function pitch(e) return M.m.floor(((E.get_prop(e,"m_flPoseParameter",0 ) or 0)* 90)+0.5) end
local function roll(e)  return E.get_prop(e,"m_angEyeAngles[2]") or 0 end
local function flags(e) return E.get_prop(e,"m_fFlags") or 1 end
local function air(e)   return M.b.band(flags(e),1)==0 end
local function vel_low(e) return (E.get_prop(e,"m_flVelocityModifier") or 1)<0.9 end
local function lby_delta(e) local l=E.get_prop(e,"m_flLowerBodyYawTarget") or 0; return M.m.abs(yaw(e)-l) end
local function sign(v)  return v<0 and "left" or "right" end
local function def_detect(e)
  if air(e) then return false end
  local low = vel_low(e)
  local pb  = pitch(e)
  local ld  = lby_delta(e)
  return (low and (pb<-15 or ld>45)) or M.m.abs(roll(e))>10
end
local function lagpeek(e)
  if not UI.get(cb_lag) then return false end
  local st=E.get_prop(e,"m_flSimulationTime") or 0; local d=st-(S.sim[e] or st); S.sim[e]=st
  return d>G.tickinterval()*8
end
local function trace_ok(e,off,hb)
  if not UI.get(cb_head) then return true end
  local lp=E.get_local_player(); if not lp then return false end
  local ex,ey,ez=C.eye_position(); local hx,hy,hz=E.hitbox_position(e,hb); if not hx then return false end
  P.set(e,"Override yaw offset",off); local _,tgt=C.trace_bullet(lp,ex,ey,ez,hx,hy,hz,false)
  return tgt==e
end
local function mesh(b,s,n)
  local t={b}
  for i=1,n do t[#t+1]=b+s*i; t[#t+1]=b-s*i end
  return t
end
local function hsv(h,s,v)
  local i = M.m.floor(h*6)
  local f = h*6 - i
  local p = v*(1-s)
  local q = v*(1-f*s)
  local t = v*(1-(1-f)*s)
  i = i % 6
  local r,g,b
  if i==0 then r,g,b=v,t,p
  elseif i==1 then r,g,b=q,v,p
  elseif i==2 then r,g,b=p,v,t
  elseif i==3 then r,g,b=p,q,v
  elseif i==4 then r,g,b=t,p,v
  else r,g,b=v,p,q end
  return M.m.floor(r*255),M.m.floor(g*255),M.m.floor(b*255)
end
------------------------------------------------------------------------
-- ◇ Classification ---------------------------------------------------
local function classify(e)
  local y=yaw(e); local d=M.m.abs(y-(S.yaw[e] or y)); S.yaw[e]=y
  if air(e)                        then return "Air" end
  if M.m.abs(roll(e))>15          then return "Roll" end
  if d>85                         then return "Flick" end
  if d>=30                        then return "Jitter" end
  if def_detect(e)                then return "Defensive" end
  return "Static"
end
------------------------------------------------------------------------
-- ◇ Offset decision --------------------------------------------------
local function choose(e,mode)
  if lagpeek(e) or air(e) then return 0 end
  if UI.get(cb_side) and S.cls[e]=="Jitter" then
    local ang = UI.get(sl_side)
    local g=(S.yaw[e] or 0)>=0 and ang or -ang
    if trace_ok(e,g,0) then return g end
  end
  local base=S.last[e] or 0
  if S.cls[e]=="Defensive" then
    for _,o in ipairs(mesh(base,20,2)) do
      if trace_ok(e,o,0) then return o end
    end
  end
  if mode=="Brute" then
    local spread = UI.get(sl_brute)
    S.idx[e]=(S.idx[e] or 0)%8+1
    return mesh(base,spread,4)[S.idx[e]]
  end
  if mode=="Learning" then return S.last[e] end
  local set=mesh(base,UI.get(sl_aggr),5)
  if mode=="Aggressive" or mode=="Novosibirsk" then
    for _,o in ipairs(set) do if trace_ok(e,o,0) then return o end end
    if UI.get(cb_body) then for _,o in ipairs(set) do if trace_ok(e,o,3) then return o end end end
  end
  if UI.get(cb_step) and (S.miss[e] or 0)>0 then
    local size = UI.get(sl_step)
    local step = (S.last[e] or 0)>=0 and size or -size
    return M.m.max(-180,M.m.min(180,(S.last[e] or 0)+step))
  end
  return base
end
------------------------------------------------------------------------
local function apply(e,cls,off)
  local py=pitch(e)
  P.set(e,"Override pitch",(cls=="Jitter" and "Up") or (py<-25 and "Down") or "Default")
  P.set(e,"Override roll", cls=="Roll" and "Straighten" or "Off")
  P.set(e,"Force safe point","Force"); P.set(e,"Force body aim","Off"); P.set(e,"Override prefer body aim","Off")
  if off then P.set(e,"Override yaw offset",off) end
end
------------------------------------------------------------------------
local function resolver()
  if not UI.get(cb_on) then return end
  local mode=UI.get(cb_mode)
  for _,e in ipairs(E.get_players(true)) do if not E.is_enemy(e) then goto next end
    local cls=classify(e); S.cls[e]=cls; local off=choose(e,mode); apply(e,cls,off)
    if G.curtime()-last_log>5 then C.color_log(200,200,255,string.format("[RM] %s  %s  off:%d\0",E.get_player_name(e),cls,off)); last_log=G.curtime() end
    ::next:: end
end
------------------------------------------------------------------------
-- ◇ Events -----------------------------------------------------------
C.set_event_callback("aim_hit", function(ev) if not UI.get(cb_on) then return end local t=ev.target; S.last[t]=P.get(t,"Override yaw offset") or 0; S.miss[t]=0 end)
C.set_event_callback("aim_miss",function(ev) if not UI.get(cb_on) then return end local t=ev.target; S.last[t]=P.get(t,"Override yaw offset") or 0; S.miss[t]=(S.miss[t] or 0)+1 end)
------------------------------------------------------------------------
-- ◇ Watermark --------------------------------------------------------
local function watermark()
  if not UI.get(cb_wm) then return end
  local txt=(UI.get(cb_mode)=="Novosibirsk" and "novosibirsk" or "t.me/aesterial")
  local sw,sh=client.screen_size(); local y=sh-18; local x=(sw/2)-renderer.measure_text("b",txt)/2
  local speed = UI.get(sl_wm_speed)*0.1
  for i=1,#txt do
    local ch=txt:sub(i,i)
    local hue=(G.curtime()*speed + i/#txt)%1
    local r,g,b=hsv(hue,1,1)
    R.text(x,y-2,r,g,b,255,"b",0,ch)
    x=x+renderer.measure_text("b",ch)
  end
end
------------------------------------------------------------------------
local function hud()
  if not UI.get(cb_on) then return end
  local r,g,b,a = UI.get(cp_col)
  local me = E.get_local_player(); if not me then return end
  local focus = C.current_threat() or me
  if focus and E.is_enemy(focus) then
    R.indicator(r,g,b,a,string.format("$ %s | %s (%s) $",E.get_player_name(focus),S.cls[focus] or "--",sign(yaw(focus))))
  end
  for _,e in ipairs(E.get_players(true)) do
    local hx,hy,hz = E.hitbox_position(e, 0)
    if not hx then goto cont end
    local sx,sy = R.world_to_screen(hx, hy, hz + 10)
    if not sx then goto cont end
    local cls = S.cls[e]
    if not cls then goto cont end
    local hue = (G.curtime()*0.4 + e*0.07)%1
    local rr,gg,bb = hsv(hue,1,1)
    R.text(sx, sy, rr, gg, bb, 255, "cb", cls)
    ::cont::
  end
  -- simple watermark
  watermark()

end
------------------------------------------------------------------------
-- ◇ Register callbacks ---------------------------------------------
C.set_event_callback("run_command", resolver)
C.set_event_callback("paint",       hud)
C.register_esp_flag("R", 255,140,160, function(ent) return S.cls[ent] and S.cls[ent] ~= "Static" end)
