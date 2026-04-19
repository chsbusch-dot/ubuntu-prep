# FUNCTIONS.md — Component Map

`ubuntu-prep-setup.sh` is one file for **distribution** (a single `curl | bash` download, zero dependencies, easy to inspect before running). Internally it's organized as ~95 small functions grouped by responsibility, with 218 BATS tests covering the dispatch logic, model recommendations, dependency graph, and component-state derivation.

This file is a jump table. Line numbers are approximate — run `grep -n '^<name>()' ubuntu-prep-setup.sh` to pin down the current location.

---

## 1. Entry point and argument parsing

| Function | Line | Purpose |
|---|---|---|
| `main` | 5147 | Top-level flow: pre-flight checks → target user → GPU detect → menu → install dispatch → summary |
| `show_usage` | 120 | Prints the `--help` text |
| (arg parser) | 130–155 | Inline `for arg in "$@"` — handles `--dry-run`, `--headless`, `--resume`, `--help` |

## 2. Pre-flight checks

| Function | Line | Purpose |
|---|---|---|
| `check_not_root` | 514 | Refuse to run as root (uses `sudo` on demand instead) |
| `check_sudo_privileges` | 522 | Prime the sudo cache; skipped in dry-run |
| `start_sudo_keepalive` | 45 | Background `sudo -v` loop so long installs don't hit cache timeout |
| `check_os` | 532 | Abort if `/etc/os-release` is not Ubuntu |
| `install_base_dependencies` | 550 | Install `curl`, `wget`, `jq`, `build-essential` etc. so later steps can assume they exist |
| `determine_target_user` | 593 | Decide whether to install for the invoking user or a different one |
| `detect_gpu` | 639 | `lspci` / `nvidia-smi` probe — sets `HAS_NVIDIA_GPU` and `GPU_STATUS` |
| `configure_timezone` | 670 | Prompt + `timedatectl set-timezone` |

## 3. Install functions (menu items)

Each maps 1:1 to a checkbox in the interactive menu. Dispatched by `MASTER_FUNCS[]` at line ~5246.

| Index | Function | Line | Installs |
|---|---|---|---|
| 0 | `update_system` | 967 | `apt-get update && full-upgrade` |
| 1 | `install_zsh` | 870 | Oh My Zsh + git/tmux/micro + plugins |
| 2 | `install_python` | 976 | python3, pip, venv |
| 3 | `install_docker` | 983 | Docker CE + Compose plugin; adds user to `docker` group |
| 4 | `install_nvm_node` | 1018 | NVM + Node LTS |
| 5 | `install_homebrew` | 1073 | Linuxbrew at `/home/linuxbrew/.linuxbrew` |
| 6 | `install_gemini_cli` | 1101 | `npm i -g @google/gemini-cli` |
| 7 | `install_nvidia_driver` | 1121 | Pinned `.run` installer; disables nouveau; reboots |
| 8 | `install_btop` | 1482 | System monitor (snap or apt) |
| 9 | `install_nvtop` | 1489 | GPU monitor (apt) |
| 10 | `install_cuda_toolkit` | 1496 | `cuda-toolkit-13` via NVIDIA apt repo |
| 11 | `install_gcc` | 1527 | CUDA-compatible gcc |
| 12 | `install_container_toolkit` | 1535 | nvidia-container-toolkit + Docker runtime hookup |
| 13 | `install_cudnn` | 1580 | cuDNN 9.21.0 via NVIDIA local .deb repo |
| 14 | `install_local_llm` | 3161 | Ollama + llama.cpp (build from source); optional Open-WebUI / LibreChat via Docker Compose |
| 15 | `install_openclaw` | 3737 | `npm i -g openclaw@beta` + onboard + systemd gateway |

## 4. Component detection, verification, cleanup

For the Local-LLM stack (Ollama/llama.cpp/Open-WebUI/LibreChat/OpenClaw), the script first **detects** current state, **verifies** health, and **cleans up** failed installs before deciding what to install. This is what makes the script idempotent — re-running finds existing components and skips or repairs them instead of redoing work.

| Function | Line | Purpose |
|---|---|---|
| `detect_local_ai_components` | 1904 | Scan for existing services/binaries, set `*_COMPONENT_STATUS` globals |
| `verify_llama_component` | 2022 | Curl-probe `/v1/models` and check systemd state |
| `verify_ollama_component` | 2039 | Curl-probe `/api/tags` |
| `verify_openwebui_component` | 2055 | Check Docker container + port |
| `verify_librechat_component` | 2075 | Check Docker stack (MongoDB + Meilisearch + rag_api + chat) |
| `verify_openclaw_component` | 2094 | Check systemd user service + gateway HTTP |
| `cleanup_llama_component` | 1963 | Remove broken llama.cpp install before reinstall |
| `cleanup_ollama_component` | 1983 | Stop + remove Ollama systemd service |
| `cleanup_openwebui_component` | 1994 | `docker compose down` + image prune |
| `cleanup_librechat_component` | 2005 | Same for LibreChat stack |
| `cleanup_openclaw_component` | 2014 | Stop user service + purge config |

## 5. Component configuration (pre-install prompts)

| Function | Line | Purpose |
|---|---|---|
| `configure_local_llm_components` | 2905 | Master menu: pick backend (Ollama / llama.cpp), frontend (WebUI/LibreChat), exposure |
| `configure_openclaw_selection` | 3110 | Prompt for release channel + port + LAN exposure |
| `configure_llm_model_prompt` | 2773 | Pick default model per backend |
| `configure_context_memory` | 2479 | Memory fit: pick ctx size, cache type, ubatch, ngl per VRAM tier |
| `edit_llama_server_parameters` | 4870 | Post-install tuning menu |
| `get_model_recommendations` | 360 | **Central config**: per-VRAM-tier recommended models for both backends |
| `get_context_defaults` | 2389 | Suggested ctx size per VRAM tier |
| `estimate_vram_usage` | 2455 | Predict VRAM consumption for (model_gb + ctx + cache_type) |
| `cache_type_bytes` | 2440 | Bytes-per-element for f16/q8_0/q4_0 etc. |
| `get_model_weight_gb` | 2374 | Lookup model size from the recommendations table |

## 6. GPU stack helpers (path + env discovery)

The NVIDIA stack (driver / CUDA / cuDNN / container toolkit) installs to different paths depending on how it was installed (.deb vs .run vs package manager). These helpers locate binaries dynamically so the rest of the script stays location-agnostic.

| Function | Line | Purpose |
|---|---|---|
| `get_cuda_nvcc_path` | 1738 | Find `nvcc` under `/usr/local/cuda*`, `/opt/nvidia/*` |
| `require_nvidia_module_loaded` | 1762 | Abort with clear error if kernel module not loaded (PCIe passthrough case) |
| `ensure_cuda_env_for_current_shell` | 1783 | Source `/etc/profile.d/cuda.sh` into current shell |
| `get_nvidia_ctk_path` | 1813 | Find `nvidia-ctk` binary |
| `ensure_nvidia_ctk_for_current_shell` | 1834 | Ensure `nvidia-ctk` is callable now |
| `get_cudnn_library_path` | 1849 | Find `libcudnn.so*` |
| `has_cudnn_available` | 1880 | Boolean probe for cuDNN |
| `ensure_cudnn_env_for_current_shell` | 1892 | Source `/etc/profile.d/cudnn.sh` into current shell |

## 7. llama.cpp / Ollama runtime helpers

| Function | Line | Purpose |
|---|---|---|
| `get_llama_repo_path` | 1660 | Standardize the llama.cpp clone location |
| `get_llama_cache_path` | 1664 | Model cache directory |
| `get_llama_runtime_pid_path` | 1668 | PID file for transient server |
| `get_llama_runtime_log_path` | 1672 | Log file for transient server |
| `get_librechat_port` | 1676 | Read current LibreChat port from compose file |
| `get_openclaw_port` | 1690 | Read current OpenClaw gateway port |
| `start_llama_server_transient` | 2326 | Start llama-server in the background for a smoke test |
| `wait_for_llama_server_ready` | 2265 | Poll `/health` until responsive or timeout |
| `wait_for_http_200` | 1704 | Generic HTTP poll helper (200 status) |
| `wait_for_http_bound` | 1721 | Generic TCP-listen poll helper |
| `build_llama_hf_args` | 2151 | Compose `--hf-repo` + `--hf-file` args for a given model |
| `download_hf_model_with_progress` | 2182 | HF Hub download with progress bar + resume |
| `llama_requires_model_selection` | 2119 | Does the current backend need the user to pick a model? |
| `llama_should_launch_server` | 2135 | Gate on whether to start llama-server at all |

## 8. Menu and UI

| Function | Line | Purpose |
|---|---|---|
| `show_menu` | 5036 | Build the render string for the interactive menu |
| `print_status_header` | 483 | Top banner showing GPU / target user / already-installed components |
| `print_header` / `print_success` / `print_info` | 468/473/478 | Colored `echo -e` wrappers |
| `format_component_status_label` | 221 | `installed` / `missing` / `broken` → human label + color |
| `format_component_action_label` | 231 | `install` / `repair` / `skip` → label |
| `record_component_outcome` | 241 | Append to `INSTALLED_COMPONENTS` / `REPAIRED_COMPONENTS` / `FAILED_COMPONENTS` |
| `print_final_summary` | 4838 | End-of-run report: URLs to access services, next steps |
| `_render_summary` | 4410 | Builds the summary body (shared by dry-run and real runs) |
| `print_dry_run_plan` | 5106 | Prints the per-component plan when `--dry-run` is passed |
| `dry_run_plan_for` | 5084 | One-liner description for each install function (index → text) |

## 9. Dispatch / dependency helpers (heavily tested)

| Function | Line | Purpose | Tests |
|---|---|---|---|
| `llama_variant_to_model_backend` | 284 | `llama_cuda` → `llama`, `llama_cpu` → `llama`, else → `llama` (default arm) | `helpers.bats` |
| `available_backend_count` | 293 | How many LLM backends are currently considered available? | |
| `need_frontend_backend_target` | 260 | Do we need the user to choose WebUI vs LibreChat? | |
| `ensure_frontend_backend_target` | 306 | Set `FRONTEND_BACKEND_TARGET` or prompt | |
| `derive_component_status` | 190 | Present + healthy → `installed`; present + unhealthy → `broken`; absent → `missing` | `components.bats` |
| `derive_component_action` | 208 | status + user intent → `install` / `repair` / `skip` | `components.bats` |
| `reset_local_ai_component_state` | 162 | Reset all `*_COMPONENT_*` globals between runs | |
| (DEP_MAP + dispatch) | 5271+ | Menu dependency graph (auto-select/cascade-remove) | `menu_deps.bats`, `deps.bats` |

## 10. Config file helpers

| Function | Line | Purpose |
|---|---|---|
| `setup_env_secrets` | 713 | Create/edit `~/.env.secrets`, chmod 600, source from `.bashrc`/`.zshrc` |
| `save_ai_settings_file` | 4856 | Persist chosen model/backend/ctx to `~/.ubuntu-prep-ai.conf` |
| `ask_yn` | 270 | Validate-or-repeat yes/no prompts (see v1.0.0 commit e91557f) |
| `curl_with_retry` | 576 | Wrapper: retry curl on transient failures | `curl_retry.bats` |

## 11. Resume-after-reboot state

Used when the NVIDIA driver install requires a reboot mid-run. State is saved to `/var/lib/ubuntu-prep/resume.env` (root-owned, chmod 600), and `--resume` re-sources it.

| Function | Line | Purpose |
|---|---|---|
| `save_resume_state` | 5938 | Serialize MASTER_SELECTIONS + completed + config vars to state file |
| `clear_resume_state` | 5978 | Remove state file + legacy resume service |
| `global_cleanup` | 19 | Trap handler: kill keepalive, revoke temp sudoers |
| `cleanup_on_error` | 34 | ERR trap: log line + delegate to `global_cleanup` |

## 12. Post-install verification

| Function | Line | Purpose |
|---|---|---|
| `check_installations` | 4248 | Probe each selected component's health |
| `verify_installations` | 4350 | Tighter per-component smoke test (used after the install loop) |

---

## Testing

- **218 BATS tests** in `tests/*.bats` cover the dispatch/dep/model/helper logic that can be unit-tested without root.
- **Static analysis**: `shellcheck -S warning` returns 0 warnings.
- **Syntax**: `bash -n ubuntu-prep-setup.sh` passes.
- **End-to-end**: validated on Ubuntu 24.04 bare metal + consumer NVIDIA, and ESXi 8.0 VM + RTXA5000-24Q vGPU (see README footer).

Additional checks run on schedule via GitHub Actions:
- `check-openclaw.yml` — daily npm package compatibility probe
- `check-nvidia-driver.yml` — daily NVIDIA driver version freshness
- `check-install-urls.yml` — daily HEAD-check of every external install URL
