import { Menu, app, shell } from "electron";
import type { MenuItemConstructorOptions } from "electron";
import { WindowManager } from "./window-manager";

export class ApplicationMenu {
  public static setup() {
    if (process.platform !== "darwin") {
      Menu.setApplicationMenu(null);
      return;
    }

    const appName = app.getName();

    const template: MenuItemConstructorOptions[] = [
      {
        label: appName,
        submenu: [
          { role: "about" },
          { type: "separator" },
          { role: "services" },
          { type: "separator" },
          { role: "hide" },
          { role: "hideOthers" },
          { role: "unhide" },
          { type: "separator" },
          { role: "quit" },
        ],
      },
      {
        label: "Edit",
        submenu: [
          { role: "undo" },
          { role: "redo" },
          { type: "separator" },
          { role: "cut" },
          { role: "copy" },
          { role: "paste" },
          { role: "pasteAndMatchStyle" },
          { role: "delete" },
          { role: "selectAll" },
        ],
      },
      {
        label: "View",
        submenu: [
          { role: "reload" },
          { role: "forceReload" },
          { role: "toggleDevTools" },
          { type: "separator" },
          { role: "resetZoom" },
          { role: "zoomIn" },
          { role: "zoomOut" },
          { type: "separator" },
          { role: "togglefullscreen" },
        ],
      },
      {
        label: "Window",
        submenu: [
          { role: "minimize" },
          { role: "zoom" },
          { type: "separator" },
          {
            label: "Show Hydra",
            accelerator: "CmdOrCtrl+Shift+H",
            click: () => WindowManager.openMainWindow(),
          },
          { type: "separator" },
          { role: "front" },
          { role: "close" },
        ],
      },
      {
        role: "help",
        submenu: [
          {
            label: "Hydra on GitHub",
            click: () =>
              shell.openExternal("https://github.com/hydralauncher/hydra"),
          },
        ],
      },
    ];

    Menu.setApplicationMenu(Menu.buildFromTemplate(template));
  }
}
