# brickbat

A menu for the Databricks CLI in the Windows terminal. See which profiles you are logged in to, log in through the browser, switch profiles, and manage secret scopes and who can use them, without remembering the commands.

> **Unofficial.** brickbat is a community tool and is not affiliated with or endorsed by Databricks, Inc. Databricks is a trademark of Databricks, Inc.

![The brickbat front page in Windows Terminal, showing the active profile, its login status and every other profile](docs/screenshots/front-page.png)

## What it does

- **Login status at a glance** for every profile in your `.databrickscfg`.
- **Log in through the browser** (`databricks auth login`), log out, switch profile, or add a new workspace.
- **A terminal for one profile**, where every `databricks` command uses the profile you picked.
- **Secret scopes:** show them all, search by name, and open one to see its keys and who has access.
- **Secrets:** add, update and delete them. Values are typed hidden or read from a file, and they are never shown.
- **Access:** grant, change or remove READ, WRITE and MANAGE.
- **One scope in every environment,** even when each environment names it differently, like `analytics.dev.secrets` and `analytics.prod.secrets`.
- **Look inside a few scopes** for a key, or for someone's access.

Works with workspaces on AWS, Azure and Google Cloud.

## Light on your workspace

Big organisations can have thousands of secret scopes. Databricks only lists keys and access one scope at a time, so brickbat never loops over every scope. Each action makes a small, known number of calls:

| Action | Calls to Databricks |
|---|---|
| Show all scopes | 1 |
| Filter the list by name | 0 |
| Search scopes by name | 1 per environment |
| Open a scope (keys and access) | 2 |
| This scope in every environment | 1 per environment, plus 2 per scope found |
| Find a key, or check someone's access, in the scopes shown | 1 per scope. Only offered when the list shows `LOOKUP_LIMIT` scopes or fewer (20 by default) |

## Requirements

- Windows 10 or 11.
- The Databricks CLI, v0.297 or newer. Install it with `winget install Databricks.DatabricksCLI`. brickbat offers to install it if it's missing.

## Install

1. Download `brickbat.bat`.
2. Put it in a folder on your `PATH`, for example `%USERPROFILE%\bin`.
3. Type `brickbat` in any terminal, or double-click the file.

If Windows warns about a file downloaded from the internet, right-click it, choose **Properties**, and tick **Unblock**.

## Using it

The front page shows your active profile and every other one. From there:

- **S** opens secret scopes.
- **P** switches profile.
- **L** logs in, and **O** logs out.
- **N** adds a workspace.
- **T** opens a terminal that uses the active profile.

![Switching profile, with every profile numbered and its login status](docs/screenshots/switch-profile.png)

**N** asks for the workspace URL and a short name, then opens your browser for the sign-in:

![Adding a new profile from a workspace URL](docs/screenshots/new-profile.png)

**T** opens a terminal where every `databricks` command uses the profile you picked:

![A terminal for the dev profile, running databricks secrets list-scopes](docs/screenshots/terminal.png)

In **Secrets**:

![The Secrets menu](docs/screenshots/secrets-menu.png)

1. **Show all scopes** lists every scope in the active workspace. Filter the list by name, then open one by its number.
2. **Search scopes by name** looks in the active workspace or in every workspace you're logged in to.
3. **Compare one scope across environments** shows its keys and access side by side.
4. **Create a new scope.**

![Every scope in the dev workspace, numbered](docs/screenshots/scope-list.png)

Once a list shows 20 scopes or fewer, two more options appear: **Find a key in these scopes** and **Check someone's access on these scopes**.

![The scope list filtered to analytics, with the key and access lookups offered](docs/screenshots/scope-filter.png)

Opening a scope shows its keys, who has access, and what you can do with it. Values are never shown:

![One scope with its secret keys, access entries and actions](docs/screenshots/scope.png)

### Scopes named per environment

Teams often put the environment in the scope name. When you compare a scope, brickbat finds the environment word in the name, between dots, underscores or dashes. It then looks for the same name with every other environment word in its place:

![Comparing analytics.*.secrets across dev, qa, prod and azure-sandbox](docs/screenshots/compare.png)

This also works for names like `ingest_dev` and `ingest_prod`. A name without an environment word is matched exactly. If two profiles point at the same workspace, that workspace is checked once.

## Settings

Change these at the top of `brickbat.bat`:

| Setting | Default | What it does |
|---|---|---|
| `SYNC_CLI_DEFAULT` | `1` | Switching profile in brickbat also makes it the CLI default (`databricks auth switch`), so plain `databricks` commands follow. With `0`, brickbat remembers its own choice and leaves the CLI default alone. |
| `LOOKUP_LIMIT` | `20` | The most scopes a key or access lookup checks, one call each. It can't be set above 50. |
| `ENV_WORDS` | `dev test tst qa uat stg stage staging preprod prod prd` | Words that mark the environment inside scope names. |

Set the environment variable `NO_COLOR=1` to turn colours off.

## Good to know

- **Group access isn't resolved.** Access lists show direct entries only, so access someone has through a group doesn't appear.
- **Permissions:** reading a scope's access needs MANAGE on it, and reading its keys needs READ. Without these, brickbat shows a short note instead.
- **Secret values are never shown.** When you add a secret, the Databricks CLI asks for the value with hidden input, or reads it from a file you choose.
- **Logging in with a token profile:** Log in runs `databricks auth login`, which signs in with OAuth in the browser. On a profile that used a personal access token, this switches the profile to OAuth.
- **Logging out:** Log out runs `databricks auth logout`, which clears cached OAuth tokens. The delete option also removes the profile from `.databrickscfg`.
- **Azure Key Vault-backed scopes** (Azure only) are read-only from Databricks. Add or change their secrets in the Key Vault. They can only be created in the workspace UI, and brickbat opens that page for you.
- **Account console profiles** can log in and out, but have no secret scopes.
- **Temporary files:** brickbat writes small files with scope and key names (never values) to `%TEMP%`, and removes them when you quit with **Q**.

## Contributing

Issues and pull requests are welcome. Two house rules:

- **Keep every action bounded.** A new feature should state how many calls it makes, and must not loop over all scopes.
- **Keep Windows line endings.** `cmd.exe` can misread labels in a `.bat` file with Unix line endings. `.gitattributes` makes Git check `.bat` files out with CRLF.

Please test changes on Windows 10 or 11, both with colours and with `NO_COLOR=1`.

## License

MIT. See [LICENSE](LICENSE).
