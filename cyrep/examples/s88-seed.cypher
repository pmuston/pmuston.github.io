// s88-seed.cypher — notional ISA-88 graph for the cyrep quickstart.
//
// Companion to: ../docs/five-minutes.md
//
// The data is entirely notional: three identical reactors in one process
// cell, using standard ISA-88 / IEC 61512 vocabulary. Nothing here comes
// from any real plant.
//
// One single CREATE statement. Valid on Neo4j 5 and graphdb >= 0.14.0.
//
// Load it:
//   cypher-shell -u neo4j -p "$NEO4J_PASSWORD" -f examples/s88-seed.cypher
//
// Expected totals after load: 66 nodes, 78 relationships.
//   Verify:  MATCH (n) RETURN count(n) AS nodes       -> 66
//   Verify:  MATCH ()-[r]->() RETURN count(r) AS rels -> 78
//
// Shape:
//   (:Area)-[:CONTAINS]->(:ProcessCell)-[:CONTAINS]->(:Unit)
//   (:Unit)-[:CONTAINS]->(:EquipmentModule)-[:CONTAINS]->(:ControlModule)
//   (:ControlModule)-[:HAS_ATTRIBUTE]->(:Attribute)   // type: PV/SP/OUT/MODE/ALARM
//   (:Unit)-[:HOSTS]->(:Phase)-[:HAS_PARAMETER]->(:Parameter)
//   (:Phase)-[:ACQUIRES]->(:EquipmentModule)
//   (:Procedure)-[:HAS_STEP]->(:UnitProcedure)-[:HAS_STEP]->(:Operation)
//   (:Operation)-[:RUNS]->(:Phase)
//
// Deliberate asymmetry, so reports exercise both branches:
//   R101 is fully populated (3 EMs, 4 CMs, 3 alarms).
//   R102 and R103 are lighter (2 EMs, 2 CMs, no alarms) — which is what
//   makes the `empty:` fallback visible in the quickstart output.
//
// To remove it again:
//   MATCH (n) WHERE n:Area OR n:ProcessCell OR n:Unit OR n:EquipmentModule
//      OR n:ControlModule OR n:Attribute OR n:Phase OR n:Parameter
//      OR n:Procedure OR n:UnitProcedure OR n:Operation
//   DETACH DELETE n

CREATE
  // --- physical hierarchy: area / cell / units ----------------------
  (area:Area {name: 'A_BUILDING2'}),
  (pc:ProcessCell {name: 'PC_TRAIN1'}),
  (area)-[:CONTAINS]->(pc),

  (r101:Unit {name: 'R101', class: 'REACTOR'}),
  (r102:Unit {name: 'R102', class: 'REACTOR'}),
  (r103:Unit {name: 'R103', class: 'REACTOR'}),
  (pc)-[:CONTAINS]->(r101),
  (pc)-[:CONTAINS]->(r102),
  (pc)-[:CONTAINS]->(r103),

  // --- R101 equipment modules and control modules (fully populated) -
  (r101agit:EquipmentModule {name: 'R101_AGIT'}),
  (r101jkt:EquipmentModule  {name: 'R101_JKT'}),
  (r101chg:EquipmentModule  {name: 'R101_CHG'}),
  (r101)-[:CONTAINS]->(r101agit),
  (r101)-[:CONTAINS]->(r101jkt),
  (r101)-[:CONTAINS]->(r101chg),

  (r101tic01:ControlModule {name: 'R101_TIC01', class: 'PID'}),
  (r101pic01:ControlModule {name: 'R101_PIC01', class: 'PID'}),
  (r101lic01:ControlModule {name: 'R101_LIC01', class: 'PID'}),
  (r101sic01:ControlModule {name: 'R101_SIC01', class: 'PID'}),
  (r101jkt)-[:CONTAINS]->(r101tic01),
  (r101chg)-[:CONTAINS]->(r101pic01),
  (r101chg)-[:CONTAINS]->(r101lic01),
  (r101agit)-[:CONTAINS]->(r101sic01),

  // R101_TIC01: standard loop attributes + high-temp alarm (feeds
  // emalarms(em: R101_JKT))
  (r101tic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R101_TIC01/PV',   type: 'PV'}),
  (r101tic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R101_TIC01/SP',   type: 'SP'}),
  (r101tic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R101_TIC01/OUT',  type: 'OUT'}),
  (r101tic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R101_TIC01/MODE', type: 'MODE'}),
  (r101tic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R101_TIC01/TAH',  type: 'ALARM'}),

  // R101_PIC01
  (r101pic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R101_PIC01/PV',   type: 'PV'}),
  (r101pic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R101_PIC01/SP',   type: 'SP'}),
  (r101pic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R101_PIC01/OUT',  type: 'OUT'}),
  (r101pic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R101_PIC01/MODE', type: 'MODE'}),

  // R101_LIC01: + high-level alarm
  (r101lic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R101_LIC01/PV',   type: 'PV'}),
  (r101lic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R101_LIC01/SP',   type: 'SP'}),
  (r101lic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R101_LIC01/OUT',  type: 'OUT'}),
  (r101lic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R101_LIC01/MODE', type: 'MODE'}),
  (r101lic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R101_LIC01/LAH',  type: 'ALARM'}),

  // R101_SIC01: + low-speed alarm (feeds emalarms(em: R101_AGIT))
  (r101sic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R101_SIC01/PV',   type: 'PV'}),
  (r101sic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R101_SIC01/SP',   type: 'SP'}),
  (r101sic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R101_SIC01/OUT',  type: 'OUT'}),
  (r101sic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R101_SIC01/MODE', type: 'MODE'}),
  (r101sic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R101_SIC01/SAL',  type: 'ALARM'}),

  // --- R102 (lighter population: two EMs, two CMs) ------------------
  (r102agit:EquipmentModule {name: 'R102_AGIT'}),
  (r102jkt:EquipmentModule  {name: 'R102_JKT'}),
  (r102)-[:CONTAINS]->(r102agit),
  (r102)-[:CONTAINS]->(r102jkt),

  (r102tic01:ControlModule {name: 'R102_TIC01', class: 'PID'}),
  (r102sic01:ControlModule {name: 'R102_SIC01', class: 'PID'}),
  (r102jkt)-[:CONTAINS]->(r102tic01),
  (r102agit)-[:CONTAINS]->(r102sic01),

  (r102tic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R102_TIC01/PV',   type: 'PV'}),
  (r102tic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R102_TIC01/SP',   type: 'SP'}),
  (r102tic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R102_TIC01/OUT',  type: 'OUT'}),
  (r102tic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R102_TIC01/MODE', type: 'MODE'}),

  (r102sic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R102_SIC01/PV',   type: 'PV'}),
  (r102sic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R102_SIC01/SP',   type: 'SP'}),
  (r102sic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R102_SIC01/OUT',  type: 'OUT'}),
  (r102sic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R102_SIC01/MODE', type: 'MODE'}),

  // --- R103 (mirror of R102) ----------------------------------------
  (r103agit:EquipmentModule {name: 'R103_AGIT'}),
  (r103jkt:EquipmentModule  {name: 'R103_JKT'}),
  (r103)-[:CONTAINS]->(r103agit),
  (r103)-[:CONTAINS]->(r103jkt),

  (r103tic01:ControlModule {name: 'R103_TIC01', class: 'PID'}),
  (r103sic01:ControlModule {name: 'R103_SIC01', class: 'PID'}),
  (r103jkt)-[:CONTAINS]->(r103tic01),
  (r103agit)-[:CONTAINS]->(r103sic01),

  (r103tic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R103_TIC01/PV',   type: 'PV'}),
  (r103tic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R103_TIC01/SP',   type: 'SP'}),
  (r103tic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R103_TIC01/OUT',  type: 'OUT'}),
  (r103tic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R103_TIC01/MODE', type: 'MODE'}),

  (r103sic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R103_SIC01/PV',   type: 'PV'}),
  (r103sic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R103_SIC01/SP',   type: 'SP'}),
  (r103sic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R103_SIC01/OUT',  type: 'OUT'}),
  (r103sic01)-[:HAS_ATTRIBUTE]->(:Attribute {name: 'R103_SIC01/MODE', type: 'MODE'}),

  // --- procedural model: phases, hosted by all three reactors -------
  (phcharge:Phase {name: 'PH_CHARGE', class: 'CHARGE'}),
  (phheat:Phase   {name: 'PH_HEAT',   class: 'HEAT'}),
  (phhold:Phase   {name: 'PH_HOLD',   class: 'HOLD'}),
  (r101)-[:HOSTS]->(phcharge), (r101)-[:HOSTS]->(phheat), (r101)-[:HOSTS]->(phhold),
  (r102)-[:HOSTS]->(phcharge), (r102)-[:HOSTS]->(phheat), (r102)-[:HOSTS]->(phhold),
  (r103)-[:HOSTS]->(phcharge), (r103)-[:HOSTS]->(phheat), (r103)-[:HOSTS]->(phhold),

  // --- phase equipment acquisition (R101 train) ----------------------
  (phcharge)-[:ACQUIRES]->(r101chg),
  (phheat)-[:ACQUIRES]->(r101jkt),
  (phheat)-[:ACQUIRES]->(r101agit),
  (phhold)-[:ACQUIRES]->(r101agit),
  (phhold)-[:ACQUIRES]->(r101jkt),

  // --- phase parameters ----------------------------------------------
  (phcharge)-[:HAS_PARAMETER]->(:Parameter {name: 'CHARGE_AMT',  kind: 'FORMULA'}),
  (phcharge)-[:HAS_PARAMETER]->(:Parameter {name: 'CHARGE_RATE', kind: 'PROCESS'}),
  (phheat)-[:HAS_PARAMETER]->(:Parameter   {name: 'TARGET_TEMP', kind: 'FORMULA'}),
  (phheat)-[:HAS_PARAMETER]->(:Parameter   {name: 'RAMP_RATE',   kind: 'PROCESS'}),
  (phhold)-[:HAS_PARAMETER]->(:Parameter   {name: 'HOLD_TIME',   kind: 'FORMULA'}),

  // --- recipe hierarchy ----------------------------------------------
  (prbatcha:Procedure     {name: 'PR_BATCH_A'}),
  (upreact:UnitProcedure  {name: 'UP_REACTION'}),
  (opreact:Operation      {name: 'OP_REACT'}),
  (prbatcha)-[:HAS_STEP]->(upreact),
  (upreact)-[:HAS_STEP]->(opreact),
  (opreact)-[:RUNS]->(phcharge),
  (opreact)-[:RUNS]->(phheat),
  (opreact)-[:RUNS]->(phhold)
