/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

// Touch gestures for the Android port (zen-android #42). Zen reveals its panel
// on mouse hover and hides it on mouse leave, neither of which exists under a
// touchscreen, and a touch that starts over web content is consumed by APZ
// before any chrome listener sees it. So MainActivity recognises the gestures
// in the raw stream above the view tree and reports them here over the app-wide
// event bus; only the two gestures we act on are reported.

const kGestureEvent = "Zen:Gesture";

function gestureDispatcher() {
  return Cc["@mozilla.org/android/bridge;1"].getService(
    Ci.nsIGeckoViewEventDispatcher
  );
}

// The coordinates arrive in surface pixels, while elementFromPoint takes CSS
// pixels of this window's viewport, which is the GeckoView surface.
function sidebarContainsPoint(aX, aY) {
  const dpr = window.devicePixelRatio || 1;
  const element = document.elementFromPoint(aX / dpr, aY / dpr);
  return !!element?.closest("#navigator-toolbox");
}

function onGesture(aEvent, aData) {
  const compactMode = gZenCompactModeManager;
  if (!compactMode?.preference) {
    return;
  }
  switch (aData?.action) {
    case "open-sidebar":
      compactMode.revealSidebar();
      break;
    case "tap":
      if (
        compactMode.sidebarRevealed() &&
        !sidebarContainsPoint(aData.x, aData.y)
      ) {
        compactMode.collapseSidebar();
      }
      break;
  }
}

if (Services.appinfo.OS === "Android") {
  gestureDispatcher().registerListener(onGesture, [kGestureEvent]);
  window.addEventListener(
    "unload",
    () => {
      gestureDispatcher().unregisterListener(onGesture, [kGestureEvent]);
    },
    { once: true }
  );
}
