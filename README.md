# Primes Godot Plugin

This is a companion editor plugin for the **Primes** platform that allows easy publishing of small Godot projects directly from the editor.

Primes is focused on lightweight, expressive projects that can be browsed and played in a mobile app, TikTok-style.

**Primes Android app:**  
https://play.google.com/store/apps/details?id=com.olelukoie.primes

*(iOS app is coming)*

---

## How to use (assuming the plugin is installed and enabled)

1. Develop your project using the **Compatibility renderer**
2. Open the **Primes** tab in the editor (next to the AssetLib tab)
3. Click **Publish**

That's it.

*Uploaded projects remain the property of their authors.
See the [Terms of Service](https://primes-app.com/tos/) for details.*

---

## What else this plugin does

Using this plugin, you also can:

- Add a name and/or description to your project (both optional)
- Run your project in the app on a connected Android phone with one click  
  *(no templates or presets needed, but requires [adb](https://developer.android.com/tools/adb) to be installed and available in PATH)*
- See a list of your already published projects
- Edit metadata or delete published projects
- View crash flags and user reports, and submit appeals

---

## Current limitations

- Published projects (exported as a compiled ZIP) must be **under 32 MB** *(this limit may change in the future)*  
  The engine itself is not included; only packaged assets and project data count toward this limit

- Projects are currently executed in the app **as Web exports**, which means:
  - Only the **Compatibility renderer** is supported
  - Native mobile rendering is **not yet available** (work in progress)

- Only an **Android app** is available at the moment  
  *(iOS is in development)*

### Execution environment restrictions

To keep the platform safe and predictable, published projects run in a restricted environment.

Some engine APIs are not available (including networking, native extensions, and certain OS features).  
The plugin checks projects for unsupported usage and will block publishing if such APIs are detected.

Only pure Godot projects using **GDScript** and built-in engine features are supported; **C# projects are not supported**.

---

## Dev notes

- The platform targets **mobile portrait mode** - landscape projects will show large black margins  
  If you must use landscape keep the portrait in settings and clearly signal to the user to rotate their phone

- The aspect ratio in the app is roughly **1:2**
  - setting viewport size to something like 1024x2048 (Project Settings -> Window -> Size) and 
  - locking a fixed ration (Project Settings -> Window -> Strech -> Aspect = keep)   
Simplifies layout and avoids the complexity of supporting many different screen sizes 

- When sizing things on screen, avoid absolute pixel values  
  Prefer ratios of viewport's width and height instead

- Read [this](https://docs.godotengine.org/en/latest/tutorials/export/exporting_for_web.html) document to understand the limitations of web exports  
  With one simplification: you don't need to worry about supporting multiple browsers

---

## How to approach Primes

Primes is a place for *everything* - weird experiments, interactive explainers, 
disturbing art, brainrot, and other things that don't fit anywhere else.

Some guiding biases for using the platform.

<details>
<summary><strong>Get to the point quickly</strong></summary>

Primes is dynamic by nature.  
Menus, settings, and long intros are often just friction.  
Start where the thing *is*.
</details>

<details>
<summary><strong>Reuse freely</strong></summary>

Assets, tools, ideas, whatever.  
Anything that is legal and helps you express yourself is fair game - just don't let it in the driver's seat.  
And if it starts feeling dishonest, it probably is.
</details>


<details>
<summary><strong>Skip the juice</strong></summary>

If you want.  
Juice doesn't make an idea better - unless it *is* the idea.
</details>

---

Expect rough edges. Feedback is welcome.
