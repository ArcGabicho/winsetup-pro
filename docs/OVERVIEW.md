# WinSetup Pro — Perfil del proyecto

## 1. Qué es

**WinSetup Pro** es un asistente en **PowerShell** que convierte una instalación
limpia de Windows en una estación de desarrollo completamente configurada, de
forma **reproducible, idempotente y segura**. Describes la máquina que quieres
(un *perfil* o una lista de *componentes*) y el motor detecta qué falta y aplica
**solo eso**. Ejecutarlo dos veces no cambia nada la segunda vez.

| | |
|---|---|
| **Tipo** | Herramienta CLI + un pequeño "Setup Engine" modular |
| **Lenguaje** | PowerShell 7 (recomendado), compatible 5.1 para bootstrap |
| **Instalación de software** | `winget` / fuentes oficiales / Microsoft Store — nunca ejecutables arbitrarios |
| **Estado** | `0.1.0` — 8 fases completas, 40 componentes, 5 perfiles, 80 tests Pester, CI |
| **Licencia** | MIT |
| **Público** | dev individual · equipos · IT · onboarding · laboratorios educativos · empresas que estandarizan · quien reinstala Windows a menudo |

---

## 2. Funciones

### 2.1 Motor (núcleo cerrado — no se toca al añadir herramientas)

| Función | Detalle |
|---|---|
| **Detección de estado** | Cada componente tiene un `Test` de solo lectura; el motor decide instalar/configurar/omitir |
| **Idempotencia** | `Install`/`Configure` solo se ejecutan si `Test` dice que hace falta |
| **Dry-run** | `-DryRun` como modo del motor: corre los `Test`, imprime el plan (`INSTALL`/`CONFIGURE`), no toca nada |
| **Journal + Resume** | `state/last-run.json` registra cada paso; `-Resume` reanuda solo lo `Pending`/`Failed` |
| **Configuración declarativa en capas** | `default.json ← perfil ← -ConfigFile ← -Install`, con JSON Schema y validación |
| **Logging estructurado** | Un archivo por ejecución en `logs/`, niveles `DEBUG…ERROR`, sin secretos |
| **Política de errores** | Interactivo: Retry/Skip/Abort · No interactivo: `errorPolicy` (crítico→abort, no crítico→skip) |
| **Detección de privilegios** | `Test-WinSetupAdmin`; los componentes declaran `RequiresAdmin` y se omiten con motivo si no hay elevación |
| **Backups consolidados** | `Backup-WinSetupFile` → `backup/<área>/<timestamp>/` antes de cualquier cambio |
| **Descubrimiento por convención** | Cualquier `modules/**/*.ps1` que devuelva un descriptor es un componente — sin registrarlo |
| **Orden por dependencias** | `DependsOn` con orden topológico y detección de ciclos |
| **Diagnóstico del host** | OS/build, arquitectura, PowerShell, winget, WSL, conectividad, disco, execution policy |

### 2.2 CLI

```
-Profile <n>   -Install <ids>   -List   -Status   -Diagnose   -Resume   -Update
-WSL   -Git   -SSH   -Dotfiles <ruta>   -DotfilesRepository <url>
globales: -DryRun  -NonInteractive  -ConfigFile <path>  -LogLevel <nivel>
sin argumentos: menú interactivo
salida: 0 ok · 1 con fallos/checks · 2 error fatal
```

### 2.3 Catálogo de componentes (40)

| Categoría | Componentes |
|---|---|
| **Development** | git, pwsh, windows-terminal, vscode, visualstudio, jetbrains-toolbox, dotnet-sdk, nodejs, npm, pnpm, python, java, go, rust, cmake, ninja, neovim, github-cli |
| **Cloud** | azure-cli, aws-cli, gcloud-cli, terraform, kubectl, helm |
| **Database** | sqlserver-tools (sqlcmd), azure-data-studio, postgresql, mysql, redis-cli, mongodb-tools, mongosh |
| **Environment** | ssh (cliente OpenSSH + claves + `~/.ssh/config`), env-vars (user/machine/PATH sin duplicados), folders (árbol `Dev\…`), fonts (Cascadia / JetBrains Mono / Fira Code per-user), wsl (WSL2, features, `.wslconfig`, distros) |
| **Customization** | powershell-profile (fragmentos + bloque gestionado en `$PROFILE`), dotfiles (carpeta o repo, prompt Y/N/S), post-install (scripts locales por hash) |

### 2.4 Perfiles

`minimal` · `frontend` · `dotnet` · `fullstack` · `enterprise` — declarativos;
cada id resuelve a un componente real; los ids no implementados se **omiten con
aviso**, nunca fallan.

---

## 3. Valor que aporta

| Segmento | Problema hoy | Valor de WinSetup Pro |
|---|---|---|
| **Dev individual** | Media jornada instalando y configurando tras reinstalar Windows | PC lista en minutos con un comando; su config vive en JSON versionable |
| **Equipo de desarrollo** | "En mi máquina funciona"; entornos que divergen | Un perfil compartido en el repo → todos con el mismo baseline verificable |
| **Departamento de IT** | Imágenes doradas pesadas y difíciles de mantener | Configuración declarativa y reversible; ejecución no interactiva con `-ConfigFile`; logs y journal auditables |
| **Onboarding de empleados** | Días de tickets para dejar operativo a alguien nuevo | `.\WinSetup.ps1 -Profile enterprise` (elevado) el día 1 |
| **Laboratorios educativos** | Reprovisionar 30 equipos idénticos cada semestre | Mismo perfil, idempotente, sin destruir datos previos; `-DryRun` para revisar |
| **Empresa que estandariza** | Deriva de estaciones, difícil de justificar en auditoría | Perfil corporativo único + backups con timestamp + política de errores explícita |
| **Reinstalador frecuente** | Repetir los mismos pasos manuales | Su `dotfiles` + perfil + `postInstall` reproducen todo |

**Diferenciadores clave:** no destructivo por defecto (detecta, respalda,
pregunta) · sin secretos en claro · sin `irm | iex` · dry-run de primera clase ·
reanudable · extensible sin reescribir el núcleo (base pensada para GUI/TUI,
ejecución remota, YAML, marketplace de módulos).

---

## 4. Flujos

### 4.1 Máquina nueva → estación lista

```
git clone  ──▶  scripts\bootstrap.ps1
                 │  (verifica PowerShell / execution policy / winget)
                 ▼
        .\WinSetup.ps1 -Diagnose            ¿host preparado? (admin, disco, red, winget)
                 ▼
        .\WinSetup.ps1 -Profile dotnet -DryRun     revisar el plan (nada cambia)
                 ▼
   (PowerShell elevado)
        .\WinSetup.ps1 -Profile dotnet
                 │  detecta → instala solo lo que falta → configura → journal
                 ▼
        "Restart recommended"  ──▶  reiniciar  ──▶  .\WinSetup.ps1 -Resume
                 ▼
        .\WinSetup.ps1 -Status              8/10 → 10/10 componentes configurados
```

### 4.2 Reanudación tras fallo o reinicio

```
Ejecución  ──▶  componente crítico falla / se pide reinicio (WSL)
                 │  journal.Completed = false ; entradas restantes = Pending
                 ▼
.\WinSetup.ps1 -Resume
                 │  re-ejecuta SOLO Pending/Failed ; lo ya hecho se omite
                 ▼
journal.Completed = true
```

### 4.3 Ejecución no interactiva (equipo / IT / CI)

```
config propia (repo)  ──▶  .\WinSetup.ps1 -Profile enterprise -ConfigFile team.json -NonInteractive
                            │  errorPolicy decide retry/skip/abort sin preguntar
                            │  admin-only sin elevación → se omite con aviso
                            ▼
                    exit 0/1/2  +  logs/*.log  +  state/last-run.json   (auditables)
```

### 4.4 Añadir una herramienta nueva (extensibilidad)

```
cp modules/Applications/_Template.ps1  modules/Applications/Ripgrep.ps1
   │  editar Id / Test (Get-WinSetupExeVersion) / Install (Install-WinSetupWingetPackage)
   ▼
.\WinSetup.ps1 -List        aparece automáticamente (sin tocar el núcleo)
.\WinSetup.ps1 -Install ripgrep
añadir "ripgrep" a profiles/frontend.json  →  entra en ese perfil
```

### 4.5 Dry-run / preview

```
-DryRun  ──▶  corre todos los Test (solo lectura)
              imprime  [SKIP] ya presente  /  [DRY] INSTALL  /  [DRY] CONFIGURE (needs elevation)
              escribe state/last-dryrun.json
              "No changes were made"
```

---

## 5. Historias de usuario

Formato: **Como** … **quiero** … **para** … — con criterios de aceptación (todos
implementados).

### Desarrollador individual

- **US-01** — Como dev que acaba de reinstalar Windows, quiero aplicar un perfil
  con un comando, para tener mi entorno en minutos.
  *Aceptación:* `-Profile minimal` instala git/pwsh/terminal/vscode/gh; una 2ª
  ejecución no reinstala nada; `-Status` muestra 5/5.
- **US-02** — Como dev, quiero previsualizar qué cambiaría antes de tocar mi
  máquina, para no romper mi configuración actual.
  *Aceptación:* `-DryRun` lista acciones y no modifica el sistema; genera
  `last-dryrun.json`.
- **US-03** — Como dev con Git ya configurado, quiero que la herramienta **no**
  pise mi `user.name`/`user.email`, para no perder mi identidad.
  *Aceptación:* si ya existen, se registran sin cambios y se avisa; `~/.gitconfig`
  se respalda antes de cualquier escritura.

### Equipo de desarrollo

- **US-04** — Como tech lead, quiero un perfil versionado en el repo, para que
  todo el equipo tenga el mismo baseline.
  *Aceptación:* `profiles/fullstack.json` declarativo; `-ConfigFile` para
  overrides del equipo; capas deep-merge.
- **US-05** — Como miembro del equipo, quiero que si un componente no crítico
  falla, el resto continúe, para no bloquear todo el setup.
  *Aceptación:* `errorPolicy.nonCritical = skip`; el resumen final reporta
  `Failed: N`; exit 1.

### Departamento de IT

- **US-06** — Como IT, quiero ejecutar el setup sin interacción y recoger
  evidencia, para auditoría y soporte.
  *Aceptación:* `-NonInteractive` + `-ConfigFile`; `logs/<timestamp>-*.log` con
  módulo/operación/resultado/duración; `state/last-run.json`.
- **US-07** — Como IT, quiero que los cambios sean reversibles, para poder
  deshacer una configuración.
  *Aceptación:* `backup/{git,ssh,wsl,powershell,environment,dotfiles}/<timestamp>/`
  antes de cada reemplazo; `scripts/uninstall.ps1` limpia datos de la herramienta
  sin desinstalar software.
- **US-08** — Como IT, quiero que la herramienta pida elevación solo cuando de
  verdad hace falta y explique por qué.
  *Aceptación:* `wsl`, `visualstudio`, `postgresql`, `mysql`, `redis-cli`,
  `env-vars(machine)`, `ssh(instalar cliente)` marcan `RequiresAdmin`; sin
  elevación se omiten con mensaje; `-DryRun` los previsualiza con
  "(needs elevation)".

### Onboarding de empleados

- **US-09** — Como empleado nuevo, quiero que mi laptop quede operativa el primer
  día con un comando.
  *Aceptación:* `-Profile enterprise` (elevado) instala IDEs, SDKs, CLIs cloud,
  WSL, fuentes, carpetas y el perfil de PowerShell; `-Resume` tras el reinicio de
  WSL.
- **US-10** — Como empleado, quiero configurar SSH para GitHub sin que nadie
  maneje mis claves.
  *Aceptación:* `ssh` detecta claves existentes y **no** las sobrescribe; ofrece
  crear una (prompt interactivo con passphrase); añade el bloque `Host github.com`
  a `~/.ssh/config` sin reescribir el resto; nunca guarda contraseñas.

### Laboratorios educativos

- **US-11** — Como profesor, quiero reprovisionar 30 PCs idénticos cada semestre
  sin borrar trabajos de alumnos.
  *Aceptación:* mismo perfil idempotente; `folders` solo crea, nunca borra; WSL
  nunca desregistra distribuciones.
- **US-12** — Como profesor, quiero fijar versiones concretas de runtimes para
  que todos los alumnos usen lo mismo.
  *Aceptación:* `dotnet.channel`, `node.channel`, `python.version`,
  `java.version`, `postgresql.version` en config.

### Empresa que estandariza estaciones

- **US-13** — Como responsable de plataforma, quiero un `.wslconfig` corporativo
  pero sin pisar el del usuario.
  *Aceptación:* `wsl.wslConfig` se escribe **solo si no existe**; para reemplazar
  hace falta `wsl.overwriteWslConfig: true` y se respalda primero.
- **US-14** — Como responsable de plataforma, quiero distribuir dotfiles
  corporativos con confirmación por archivo.
  *Aceptación:* `-DotfilesRepository <url>` clona en `state/dotfiles/`; por
  archivo que difiera, prompt **Y/N/S**; backups versionados; nunca borra.

### Usuario que reinstala Windows a menudo

- **US-15** — Como power user, quiero que mi máquina "ideal" esté descrita en un
  archivo para reproducirla cuando quiera.
  *Aceptación:* un `-ConfigFile` con `applications` + `git` + `environment` +
  `folders` + `fonts` + `powershellProfile` + `dotfiles` + `postInstall`
  regenera todo; 2ª ejecución = 0 cambios.
- **US-16** — Como power user, quiero ejecutar mis propios scripts de remate al
  final, una sola vez.
  *Aceptación:* `postInstall.scripts` corre `.ps1` locales, registrados por hash
  en `state/postinstall.json`; sin cambios no se repiten; nunca descarga scripts
  remotos.

### Contribuidor / mantenedor

- **US-17** — Como contribuidor, quiero añadir un componente sin entender todo el
  motor.
  *Aceptación:* copiar `_Template.ps1`, implementar `Test`/`Install`;
  `docs/MODULES.md` con contrato, ciclo de vida y helpers; el descubrimiento es
  automático.
- **US-18** — Como mantenedor, quiero CI que garantice que ningún perfil
  referencia ids inexistentes y que la suite pasa.
  *Aceptación:* `.github/workflows/ci.yml` (syntax check + PSScriptAnalyzer + 80
  tests Pester en `windows-latest`); `Profiles.Tests.ps1` valida que cada perfil
  resuelve y hace dry-run limpio.
