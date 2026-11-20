# Validación de datos contra el diccionario

Fecha de ejecución: 2026-11-20

Datos simulados. Referencia: `data/diccionario_datos.csv`.

- Variables validadas: 28
- Variables con estado REVISAR: 0
- Valores faltantes en total: 0
- Valores fuera de rango o de niveles esperados: 0
- `sample_id` repetidos (suma de las tres capas): 0
- Estado general: OK

Para variables de tipo factor, `fuera_de_rango` cuenta valores fuera de los niveles esperados; para `sample_id`, cuenta duplicados.

| variable | capa | unidad | n | n_NA | min | max | rango esperado | fuera_de_rango | estado |
|---|---|---|---|---|---|---|---|---|---|
| sample_id | metadatos | sin unidad | 40 | 0 | - | - | 40 valores únicos (uno por muestra) | 0 | OK |
| bloque | metadatos | sin unidad | 40 | 0 | - | - | Bloque_1; Bloque_2; Bloque_3; Bloque_4 | 0 | OK |
| tratamiento | metadatos | sin unidad | 40 | 0 | - | - | Control; Calor | 0 | OK |
| genotipo | metadatos | sin unidad | 40 | 0 | - | - | G1; G2; G3; G4; G5 | 0 | OK |
| A_net | fisiologia | µmol CO2 m⁻² s⁻¹ | 40 | 0 | 8.32 | 25.32 | 5 a 30 | 0 | OK |
| gs | fisiologia | mol H2O m⁻² s⁻¹ | 40 | 0 | 0.11 | 0.372 | 0.05 a 0.60 | 0 | OK |
| Ci | fisiologia | µmol mol⁻¹ | 40 | 0 | 191.2 | 327.7 | 150 a 400 | 0 | OK |
| E | fisiologia | mmol H2O m⁻² s⁻¹ | 40 | 0 | 1.34 | 4.81 | 0.5 a 8 | 0 | OK |
| Fv_Fm | fisiologia | adimensional | 40 | 0 | 0.65 | 0.832 | 0.60 a 0.85 | 0 | OK |
| SPAD | fisiologia | unidades SPAD | 40 | 0 | 30.4 | 48.5 | 20 a 60 | 0 | OK |
| CTD | fisiologia | °C | 40 | 0 | 0.96 | 5.35 | 0 a 8 | 0 | OK |
| K_mg_g | ionomica | mg g⁻¹ de materia seca | 40 | 0 | 25.88 | 41.2 | 20 a 50 | 0 | OK |
| Na_mg_g | ionomica | mg g⁻¹ de materia seca | 40 | 0 | 1.1 | 1.97 | 0.5 a 3 | 0 | OK |
| Ca_mg_g | ionomica | mg g⁻¹ de materia seca | 40 | 0 | 7.65 | 12.51 | 5 a 15 | 0 | OK |
| Mg_mg_g | ionomica | mg g⁻¹ de materia seca | 40 | 0 | 2.79 | 3.61 | 2 a 5 | 0 | OK |
| P_mg_g | ionomica | mg g⁻¹ de materia seca | 40 | 0 | 3.52 | 4.87 | 2 a 6 | 0 | OK |
| Fe_ug_g | ionomica | µg g⁻¹ de materia seca | 40 | 0 | 100.4 | 121.5 | 80 a 150 | 0 | OK |
| Zn_ug_g | ionomica | µg g⁻¹ de materia seca | 40 | 0 | 35.8 | 45.6 | 25 a 60 | 0 | OK |
| Mn_ug_g | ionomica | µg g⁻¹ de materia seca | 40 | 0 | 57.3 | 72.9 | 40 a 100 | 0 | OK |
| Glucosa | metabolomica | u.a. | 40 | 0 | 74.93 | 138.23 | 50 a 160 | 0 | OK |
| Fructosa | metabolomica | u.a. | 40 | 0 | 60.87 | 95.42 | 40 a 110 | 0 | OK |
| Sacarosa | metabolomica | u.a. | 40 | 0 | 52.6 | 112.02 | 40 a 130 | 0 | OK |
| Rafinosa | metabolomica | u.a. | 40 | 0 | 21.54 | 51.97 | 10 a 70 | 0 | OK |
| Prolina | metabolomica | u.a. | 40 | 0 | 32.94 | 73.16 | 20 a 90 | 0 | OK |
| GABA | metabolomica | u.a. | 40 | 0 | 41.67 | 82.71 | 30 a 100 | 0 | OK |
| Malato | metabolomica | u.a. | 40 | 0 | 48.46 | 80.87 | 30 a 100 | 0 | OK |
| Citrato | metabolomica | u.a. | 40 | 0 | 32.48 | 67.78 | 20 a 90 | 0 | OK |
| tipo_dato | metabolomica | sin unidad | 40 | 0 | - | - | simulado | 0 | OK |
