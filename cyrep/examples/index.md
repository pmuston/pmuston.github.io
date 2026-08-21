---
title: cyrep examples
---

[← cyrep](../)

# Examples

Everything here runs against `s88-seed.cypher`, a notional ISA-88 batch plant —
one area, one process cell, three reactor units with their equipment and control
modules, and a recipe that runs three phases. It is entirely invented and uses
standard public S88 vocabulary.

The three reactors are deliberately uneven: R101 is fully populated and has
alarms, R102 and R103 do not. That asymmetry is what makes the `empty:` fallback
visible in the reports.

| File | What it shows |
| ---- | ------------- |
| [s88-seed.cypher](s88-seed.cypher) | The graph. 66 nodes, 78 relationships, one `CREATE`. |
| [s88_quickstart.yaml](s88_quickstart.yaml) | One section per unit — roughly where [the 5-minute walkthrough](../demo/) ends up. |
| [s88_physical_model.yaml](s88_physical_model.yaml) | `forEach` nested three deep, down the equipment hierarchy. |
| [s88_recipe_procedure.yaml](s88_recipe_procedure.yaml) | The procedural side: procedures, unit procedures, operations and phases. |
| [module_reference.yaml](module_reference.yaml) | The canonical minimal example, against a simpler `Module` schema. |

```bash
curl -fsSLO https://pmuston.github.io/cyrep/examples/s88-seed.cypher
cypher-shell -u neo4j -p "$NEO4J_PASSWORD" -f s88-seed.cypher

curl -fsSLO https://pmuston.github.io/cyrep/examples/s88_quickstart.yaml
cyrep run s88_quickstart.yaml --output units.md
```

Every `ORDER BY` in these reports is a total order, deliberately — see the
[authoring guide](../authoring/) for why that is the author's job and not the
engine's.
