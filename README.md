# skeetresolver

Enhanced resolver script for the gamesense/skeet API with jitter correction and
Neverlose AA heuristics.

Features
--------
- Animated gradient watermark
- Colourful indicators above enemies with gradient text
- Jitter resolver and defensive detection
- Neverlose AA resolver for "NL" style antiaim

## Recommended Settings
- Resolver: **Enable**
- Resolver Mode: **Balanced**
- Adaptive step: **On** with *Step size* **15°**
- Jitter correction: **On** with *Guess angle* **60°**
- Defensive spread: **20°**
- Balanced spread: **25°**
- Watermark enabled with speed **5x**
- Indicator colour: `80 150 255 255`

These values generally provide solid results but may require tuning for specific servers.
