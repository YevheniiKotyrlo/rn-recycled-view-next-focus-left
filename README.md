# Android: a recycled View keeps its `nextFocusLeft`

With view recycling on, a `View` that mounts in place of one that had `nextFocusLeft` gets the old view's Android view
back with `nextFocusLeftId` still set, so Arrow Left (D-pad Left) from it goes to the old target.
`BaseViewManager.prepareToRecycleView` resets `nextFocusDown`, `nextFocusForward`, `nextFocusRight` and `nextFocusUp`,
but not `nextFocusLeft`.

`MainApplication.kt` turns the `enableViewRecycling` feature flag on after `loadReactNative`. `ReproducerApp/App.tsx`
renders a row of three focusable `Pressable`s: "Target", "Neighbour" and "Old subject", whose `nextFocusLeft` is
"Target". Once Arrow Left from "Old subject" has focused "Target", "Old subject" unmounts, and a second later
"New subject", without `nextFocusLeft`, mounts in its place. `MainActivity.kt` logs which Android view instance each
subject is drawn by and its `nextFocusLeftId`.

```sh
./reproduce.sh
```

`reproduce.sh` builds the release APK for the attached device, installs and starts it, presses Arrow Right until
"Old subject" holds focus, then Arrow Left; once "New subject" shows, it presses Arrow Right until "New subject" holds
focus, then Arrow Left, and reads which view holds focus from `uiautomator dump`. It needs adb with one Android device
attached (`ANDROID_SERIAL` picks one of several), node, yarn and a JDK.

Expected: Arrow Left from "New subject" focuses "Neighbour", the view on its left. Seen: it focuses "Target".

Exit 1 while Arrow Left from "New subject" focuses "Target", 0 once it focuses "Neighbour", 2 when another step fails —
among them Arrow Left from "Old subject" not reaching "Target", or "New subject" not reusing "Old subject"'s Android
view.
