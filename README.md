# Quest XP Forecast

Preview quest turn-in XP on the default experience bar in World of Warcraft: Forever.

- See XP from quests ready to turn in and quests still in progress.
- Hover over the bar for the breakdown and how much XP you would still need after turning in those quests.
- Enable **Tracked quests only** to forecast just the quests on your objective tracker.
- Customize each fill's color and opacity and the font size in **Options > AddOns > Quest XP Forecast**. The draggable minimap button opens the same settings.

## Installation

Install through CurseForge once the project is approved, or download the addon ZIP from [GitHub Releases](https://github.com/iltGames/QuestXPForecast/releases) and extract it into `_forever_/Interface/AddOns`. The ZIP contains the `ForeverQuestXP` folder. Keeping this folder name preserves settings from earlier versions.

If BetterBlizzFrames' Quest XP Bar is enabled, both addons will draw a forecast. Disable that option in BetterBlizzFrames to use this addon's forecast.

## Development

Edit the files in this repository. To test locally on Windows, run this from PowerShell at the repository root and pass your Forever client's AddOns path:

```powershell
./scripts/Install-Dev.ps1 -AddOnsPath 'C:/Blizzard Games/World of Warcraft/_forever_/Interface/AddOns'
```

This installs an independently named **Quest XP Forecast (Dev)** addon with its own settings. In WoW's AddOns list, enable either the dev or stable addon for the character you are testing. Restart the client to detect the dev addon the first time, then use `/reload` after subsequent dev installs. CurseForge can continue updating the stable folder.

## Release

Bump `## Version` in `ForeverQuestXP.toc` and push it to `main`. As with TotemDeck, that change builds an installable ZIP and publishes a GitHub release for the new version. Upload the same ZIP in the CurseForge author portal as a **Release** for **Forever / 1.60.1**.

MIT © iltGames
