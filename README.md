# brickbat

A menu for the Databricks CLI in the Windows terminal. Log in, switch profiles and manage secret scopes without remembering the commands.

![brickbat in Windows Terminal](docs/screenshots/front-page.png)

- See which profiles you're logged in to, and log in through the browser.
- Switch profile, add a workspace, or open a terminal for one profile.
- Browse and search secret scopes, add or delete secrets, and manage who has access.
- Compare one scope across dev, qa and prod.

Works with Databricks on AWS, Azure and Google Cloud.

## Install

You need Windows 10 or 11 and the Databricks CLI v0.297 or newer (`winget install Databricks.DatabricksCLI`).

1. Download [`brickbat.bat`](brickbat.bat).
2. Put it in a folder on your `PATH`.
3. Run `brickbat`.

## More

The [guide](docs/GUIDE.md) has screenshots of every screen, the settings, and the details.

---

Unofficial, and not affiliated with Databricks, Inc. MIT [license](LICENSE).
