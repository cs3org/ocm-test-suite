import { describe, expect, test } from "bun:test";
import { redirectWindowOpenInSameWindow } from "../../cypress/support/adapters/cernbox/shared/files";

function makeMockWindow(): { win: Window; assignCalls: string[] } {
  const assignCalls: string[] = [];
  const win = {
    name: "",
    location: {
      assign: (url: string) => {
        assignCalls.push(url);
      },
    },
  } as unknown as Window;
  return { win, assignCalls };
}

describe("redirectWindowOpenInSameWindow", () => {
  test("redirects a non-empty string URL via location.assign", () => {
    const { win, assignCalls } = makeMockWindow();
    const result = redirectWindowOpenInSameWindow(
      win,
      "https://cernbox.example.test/files/editor/abc",
    );
    expect(assignCalls).toEqual([
      "https://cernbox.example.test/files/editor/abc",
    ]);
    expect(result).toBe(win);
  });

  test("redirects a URL object via location.assign(String(url))", () => {
    const { win, assignCalls } = makeMockWindow();
    const url = new URL("https://cernbox.example.test/files/share/xyz");
    const result = redirectWindowOpenInSameWindow(win, url);
    expect(assignCalls).toEqual([url.toString()]);
    expect(result).toBe(win);
  });

  test("does not redirect for undefined, null, or empty string", () => {
    for (const url of [undefined, null, ""] as const) {
      const { win, assignCalls } = makeMockWindow();
      const result = redirectWindowOpenInSameWindow(win, url);
      expect(assignCalls).toEqual([]);
      expect(result).toBe(win);
    }
  });

  test("names the window but does not navigate on an about:blank preopen", () => {
    const { win, assignCalls } = makeMockWindow();
    const result = redirectWindowOpenInSameWindow(win, "about:blank", "ocm-remote-1");
    expect(assignCalls).toEqual([]);
    expect((win as unknown as { name: string }).name).toBe("ocm-remote-1");
    expect(result).toBe(win);
  });

  test("names the window and navigates in-tab for a real launch target", () => {
    const { win, assignCalls } = makeMockWindow();
    const result = redirectWindowOpenInSameWindow(
      win,
      "https://jupyterhub1.docker/services/ocm/open",
      "ocm-remote-2",
    );
    expect((win as unknown as { name: string }).name).toBe("ocm-remote-2");
    expect(assignCalls).toEqual([
      "https://jupyterhub1.docker/services/ocm/open",
    ]);
    expect(result).toBe(win);
  });
});
