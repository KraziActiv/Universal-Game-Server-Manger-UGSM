# UniversalGameServerManager

KraziActiv's Universal Game Server Manager - User Guide
=======================================================

Welcome to the Universal Game Server Manager! This tool simplifies the process of setting up, configuring, and managing dedicated servers for various games like DayZ, SCUM, 7 Days to Die, ARK, and more.

1. GETTING STARTED & PREREQUISITES
----------------------------------
Before you can install any game servers, you must set up SteamCMD. This is the official command-line tool from Valve used to download server files.

IMPORTANT: DISK SPACE
Game servers can be very large (often 10GB - 50GB+ each). 
We strongly recommend installing SteamCMD and this application on a drive with plenty of free space (e.g., D:\ or E:\), rather than your main C:\ drive if it is small.

2. GLOBAL SETTINGS (First Run)
------------------------------
When you first open the app, go to the "Global Settings" tab.

- SteamCMD Path: 
  If you already have SteamCMD, click "Browse" to select `steamcmd.exe`.
  If not, click "Download & Install". Select a folder on your large drive (e.g., `D:\SteamCMD`). The app will download it and run it once to initialize.

- Steam Credentials:
  Most game servers (SCUM, 7D2D, ARK, etc.) can be downloaded anonymously. You can leave the Username/Password fields blank.
  Some games (like DayZ) may require a valid Steam account to download server files. If needed, enter your Steam username and password here.

Click "Save Global Settings" when done.

3. ADDING A SERVER
------------------
1. Go to the "Server Management" tab.
2. Click "Add Server".
3. Enter a "Server Name" (this is just for the manager list, but often used as the default in-game name too).
4. Select the "Game" from the dropdown list.
5. Click "Add Server".

This creates the folder structure for your server but does NOT download the game files yet.

4. INSTALLING SERVER FILES
--------------------------
1. Select your new server from the list on the left.
2. Go to the "Server Control" tab.
3. Click the "Install / Update Files" button.
   - This will open a SteamCMD window and begin downloading the game server files.
   - This process can take a long time depending on your internet speed and the game size.
   - Wait for the "Success" message.

5. CONFIGURING YOUR SERVER
--------------------------
Once installed, you can configure your server settings.
1. With the server selected, look for the game-specific tabs (e.g., "DayZ Settings", "SCUM Settings", "ARK Settings").
2. These tabs provide easy-to-use controls for common settings like Server Name, Password, Max Players, etc.
3. Always click "Save Settings" at the top of the tab after making changes.

6. RUNNING THE SERVER
---------------------
1. Go to the "Server Control" tab.
2. Click "Start Server".
3. The server console output (or a summary) will appear in the black console window.
4. To stop the server, click "Stop Server". The manager attempts a graceful shutdown (saving the game) before forcing it to close.
