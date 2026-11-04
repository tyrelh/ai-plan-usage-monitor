# AI plan usage

Usage information for a person's Claude Code, Codex, and Kimi Code subscriptions, shown together for quick comparison.

## Language

**Provider**:
The service whose subscription usage is shown: Claude Code, Codex, or Kimi Code.

**Usage window**:
A provider-defined period over which subscription usage is measured, such as five hours, seven days, or one month. Each window has its own utilization and reset time.

**Utilization**:
The percentage of a usage window's allowance already consumed, as reported by the provider.
_Avoid_: Balance, remaining usage

**Reset time**:
The time a usage window's allowance is scheduled to become available again, as reported by the provider.

**Reading**:
The latest successfully retrieved utilization and reset time for a provider's usage windows, with the time it was retrieved. A reading is stale when a later refresh fails.
_Avoid_: Live usage

**Unavailable window**:
A usage window for which the provider has not supplied a usable utilization value. It is distinct from a window reporting zero utilization.

**Extra usage**:
Claude usage billed against credits after the included subscription allowance. It is separate from the five-hour and seven-day utilization windows.
