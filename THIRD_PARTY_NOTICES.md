# Third-Party Notices

## Agent Shell

The optional module
`emacs.d/config/modules/61_ear_agent_shell.org` integrates EAR with
[xenodium/agent-shell](https://github.com/xenodium/agent-shell).

- Upstream author: Alvaro Ramirez
- Upstream license: GNU General Public License version 3 or later
- Installation: external MELPA/Elpaca package
- Dependencies: `acp.el` and `shell-maker`; both are GPL version 3 or later and
  are installed from package metadata rather than copied into this repository
- Local integration license: GPL-3.0-or-later, declared in the module header

No Agent Shell source files are vendored or modified here. The integration
uses the public `agent-shell-make-agent-config`, `agent-shell-start`, and
`acp-make-client` APIs.
