# Wisp working guidance

Read [the deliberate choices](docs/intent.md) before changing or flagging apparently inconsistent editor or theme behavior. Keep their rationale there. User-facing use, configuration, build, and signing instructions belong in [README.md](README.md).

Use `scripts/test.sh` for Swift Testing; it supplies the Command Line Tools framework paths. Use `scripts/install.sh` for app implementation changes and the Swift skill's installation verification.

Before changing editor analysis, rendering, or resource usage, read [the resource design](docs/design-resource-usage.md) and [remaining plan](docs/plan-resource-usage.md). Use exact UTF-16 equality when reusing offset-based analysis, and keep the full renderer as the reference for local styling; differential attribute tests cover the latter.

For allocation work, start with the plan's [profiling workflow](docs/plan-resource-usage.md#allocation-profiling-workflow) and `scripts/profile-allocations.py`. Keep results outside the checkout, use matched workload counts, and distinguish scripted component measurements from installed-app behavior. Use disposable fixtures and preferences rather than the user's scratchpad.

Keep architecture decisions and remaining work in `docs/`; link to them here instead of duplicating them or recording profiling results in agent instructions.
