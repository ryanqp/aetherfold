# First contribution

1. Install Godot 4.7 Standard (not .NET). Import the folder that contains `project.godot`. Press F5 and play one match against the bot from **Vs. AI**.
2. From the project root, run the tests:

```
godot --headless --path . -s res://tools/run_tests.gd
```

Exit code 0 and `failed: 0` means the suite is green. Details: [testing.md](testing.md).

3. Read [adding-a-card.md](adding-a-card.md). If a sentence is unclear, fix that sentence in the same pull request.
4. Branch off `main`, keep the change small, and open a pull request. Say which issue it closes.

More layout notes: [../CONTRIBUTING.md](../CONTRIBUTING.md). Words like commander, tap, and stack: [glossary.md](glossary.md).
