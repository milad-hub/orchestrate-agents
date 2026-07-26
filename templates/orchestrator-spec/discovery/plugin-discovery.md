# Plugin Discovery

Sources, all read-only:
1. `{{AGENT_HOME_DIR}}/settings.json` → `enabledPlugins` map (`name@marketplace`:
   true/false). `false` = installed but disabled → PROHIBITED.
2. Session listings: plugin skills appear in the skills listing
   (`plugin:skill` names), plugin agents in the agent-types listing
   (`plugin:agent` names), plugin commands as `/plugin:command`.
3. Plugin manifests under `{{AGENT_HOME_DIR}}/plugins/marketplaces/` for deeper
   inspection (agent frontmatter, hooks) when routing decisions need it.

Rules:
- A plugin absent from the session listings is unavailable regardless of
  settings — do not recommend it.
- Plugin hooks run automatically; catalog them for awareness (they may
  rewrite commands or inject context) but never recommend "using" a hook —
  hooks are not invocable capabilities.
- Never enable, disable, reinstall, update, or reconfigure plugins during
  orchestration.
- Nothing is known-disabled at ship time — this bundle makes no
  assumption about which plugins are installed/enabled on the target
  machine. Discovery each run (and `/orchestrate-sync` once after
  install) finds whatever is actually disabled and adds it to
  `capabilities.explicitDeny`.
