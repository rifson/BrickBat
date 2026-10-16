# brickbat guide

[Back to the README](../README.md)

- [Install](#install)
- [Profiles](#profiles)
- [Secrets](#secrets)
- [Comparing a scope across environments](#comparing-a-scope-across-environments)
- [Settings](#settings)
- [How many calls it makes](#how-many-calls-it-makes)
- [Good to know](#good-to-know)

## Install

1. Install the Databricks CLI v0.297 or newer: `winget install Databricks.DatabricksCLI`. brickbat offers to install it if it's missing.
2. Download `brickbat.bat` and put it in a folder on your `PATH`, for example `%USERPROFILE%\bin`.
3. Type `brickbat` in any terminal, or double-click the file.

If Windows warns about a file downloaded from the internet, right-click it, choose **Properties**, and tick **Unblock**.

## Profiles

The front page shows the active profile, whether you're logged in, and every other profile in your `.databrickscfg`.

![The front page](screenshots/front-page.png)

| Key | Does |
|---|---|
| **S** | Secrets |
| **P** | Switch profile |
| **T** | Open a terminal for this profile |
| **L** / **O** | Log in / log out |
| **N** | Add a new profile |
| **W** | Open the workspace in the browser |
| **I** | Versions, settings, and updating the CLI |

**P** lists every profile by number:

![Switching profile](screenshots/switch-profile.png)

**N** asks for the workspace URL and a short name, then opens your browser to sign in:

![Adding a profile](screenshots/new-profile.png)

**T** opens a terminal where every `databricks` command uses that profile. Type `exit` to go back.

![A terminal for the dev profile](screenshots/terminal.png)

## Secrets

![The Secrets menu](screenshots/secrets-menu.png)

**Show all scopes** lists every scope in the workspace. Open one by its number, or filter by name.

![Every scope in the workspace](screenshots/scope-list.png)

Once a list is down to 20 scopes or fewer, you can also look inside them for a key, or for someone's access.

![A filtered list](screenshots/scope-filter.png)

Opening a scope shows its keys and who has access. From here you can add, update or delete secrets, and grant, change or remove READ, WRITE and MANAGE. Secret values are never shown.

![One scope](screenshots/scope.png)

## Comparing a scope across environments

Teams often put the environment in the scope name, like `analytics.dev.secrets` and `analytics.prod.secrets`. When you compare a scope, brickbat swaps the environment word for each of the others and shows what it finds in every workspace you're logged in to:

![One scope in every environment](screenshots/compare.png)

The environment word can sit between dots, underscores or dashes, so `ingest_dev` and `ingest_prod` match too. A name without an environment word is matched exactly. If two profiles point at the same workspace, it's checked once.

## Settings

Change these at the top of `brickbat.bat`:

| Setting | Default | What it does |
|---|---|---|
| `SYNC_CLI_DEFAULT` | `1` | Switching profile also makes it the CLI default (`databricks auth switch`). With `0`, brickbat keeps its own choice and leaves the CLI default alone. |
| `LOOKUP_LIMIT` | `20` | The most scopes a key or access lookup checks, one call each. At most 50. |
| `ENV_WORDS` | `dev test tst qa uat stg stage staging preprod prod prd` | Words that mark the environment inside scope names. |

Set the environment variable `NO_COLOR=1` to turn colours off.

## How many calls it makes

Workspaces can have thousands of secret scopes, and Databricks only lists keys and access one scope at a time. brickbat never loops over every scope:

| Action | Calls to Databricks |
|---|---|
| Show all scopes | 1 |
| Filter the list by name | 0 |
| Search scopes by name | 1 per environment |
| Open a scope | 2 |
| One scope in every environment | 1 per environment, plus 2 per scope found |
| Find a key, or someone's access, in the scopes shown | 1 per scope, only for `LOOKUP_LIMIT` scopes or fewer |

## Good to know

- **Group access isn't resolved.** Access lists show direct entries only.
- **Permissions:** seeing a scope's access needs MANAGE on it, and seeing its keys needs READ.
- **Token profiles:** Log in uses OAuth in the browser, so a profile that used a personal access token switches to OAuth.
- **Log out** clears the cached login. The delete option also removes the profile from `.databrickscfg`.
- **Azure Key Vault-backed scopes** are read-only from Databricks. Change their secrets in the Key Vault.
- **Account console profiles** can log in and out, but have no secret scopes.
- **Temporary files:** brickbat writes scope and key names (never values) to `%TEMP%` and removes them when you quit with **Q**.
