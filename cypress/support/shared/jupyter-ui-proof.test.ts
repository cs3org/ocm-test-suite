import { describe, expect, test } from "bun:test";
import { jupyterLabReadySelector, jupyterLabUiSelector } from "./jupyter-ui-proof";

describe("jupyterLabUiSelector", () => {
  test("targets stable JupyterLab shell markers", () => {
    expect(jupyterLabUiSelector).toContain("#jupyterlab");
    expect(jupyterLabUiSelector).toContain(".jp-LabShell");
    expect(jupyterLabUiSelector).toContain("[data-jp-main-area]");
    expect(jupyterLabUiSelector).toContain(".jp-NotebookPanel");
    expect(jupyterLabUiSelector).toContain(".jp-Launcher");
    expect(jupyterLabUiSelector).toContain(".jp-FileBrowser");
  });

  test("does not treat hub login pages as Lab shell proof", () => {
    expect(jupyterLabUiSelector).not.toContain("hub/login");
    expect(jupyterLabUiSelector).not.toContain("jp-Login");
  });
});

describe("jupyterLabReadySelector", () => {
  test("targets content-level JupyterLab widgets", () => {
    expect(jupyterLabReadySelector).toContain(".jp-Launcher");
    expect(jupyterLabReadySelector).toContain(".jp-LauncherCard");
    expect(jupyterLabReadySelector).toContain(".jp-FileBrowser");
    expect(jupyterLabReadySelector).toContain(".jp-Notebook");
    expect(jupyterLabReadySelector).toContain(".jp-MainAreaWidget");
  });

  test("does not rely on the shell container alone", () => {
    expect(jupyterLabReadySelector).not.toContain(".jp-LabShell");
    expect(jupyterLabReadySelector).not.toContain("#jupyterlab");
  });
});
