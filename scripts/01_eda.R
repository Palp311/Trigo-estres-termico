# Análisis exploratorio de datos simulados de fisiología, ionómica y metabolómica.
paquetes_requeridos <- c("dplyr", "tidyr", "ggplot2", "readr", "here")
paquetes_faltantes <- paquetes_requeridos[
  !vapply(paquetes_requeridos, requireNamespace, logical(1), quietly = TRUE)
]
if (length(paquetes_faltantes) > 0) {
  stop("Instala los paquetes faltantes: ", paste(paquetes_faltantes, collapse = ", "))
}
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(readr)
  library(here)
})

# Rutas y metadatos comunes a las tres capas
dir_datos <- here("data", "raw")
dir_salida <- here("data", "processed")
dir_figuras <- here("figures")
dir_reportes <- here("reports")
metadatos <- c("sample_id", "bloque", "tratamiento", "genotipo")

# Lee una capa y valida lectura, metadatos y unicidad de sample_id
leer_capa <- function(nombre_archivo) {
  ruta <- file.path(dir_datos, nombre_archivo)
  if (!file.exists(ruta)) stop("Falta el archivo de entrada: ", ruta)
  datos <- read_csv(
    ruta,
    na = c("", "NA", "N/A", "-9999"),
    show_col_types = FALSE
  )
  if (nrow(problems(datos)) > 0) stop("Problemas de lectura en: ", ruta)
  metadatos_faltantes <- setdiff(metadatos, names(datos))
  if (length(metadatos_faltantes) > 0) {
    stop("Faltan metadatos en ", nombre_archivo, ": ", paste(metadatos_faltantes, collapse = ", "))
  }
  if (anyNA(datos[metadatos])) stop("Faltan metadatos en: ", nombre_archivo)
  if (anyDuplicated(datos$sample_id)) stop("sample_id repetido en: ", nombre_archivo)
  datos
}

fisiologia <- leer_capa("physiology_simulated.csv")
ionomica <- leer_capa("ionomics_simulated.csv")
metabolomica <- leer_capa("metabolomics_simulated.csv")

# Comprueba que la capa candidata comparta muestras y metadatos con la de referencia
verificar_alineacion <- function(referencia, candidata, nombre_capa) {
  if (!setequal(referencia$sample_id, candidata$sample_id)) {
    stop("sample_id difiere en ", nombre_capa)
  }
  metadatos_sin_par <- anti_join(
    select(referencia, all_of(metadatos)),
    select(candidata, all_of(metadatos)),
    by = metadatos
  )
  if (nrow(metadatos_sin_par) > 0) stop("Los metadatos difieren en ", nombre_capa)
}
verificar_alineacion(fisiologia, ionomica, "ionómica")
verificar_alineacion(fisiologia, metabolomica, "metabolómica")

# ---- Validación contra el diccionario de datos --------------------------------
diccionario <- read_csv(here("data", "diccionario_datos.csv"), show_col_types = FALSE)

# Valida las variables de una capa contra el diccionario. Los problemas
# estructurales (columnas sin documentar o ausentes) detienen el script; los
# valores fuera de rango o de niveles solo se reportan (estado "REVISAR").
validar_capa <- function(datos, diccionario, capa, variables, nombre_capa = capa) {
  dic <- filter(diccionario, capa == !!capa)
  sin_documentar <- setdiff(variables, dic$variable)
  if (length(sin_documentar) > 0) {
    stop("Columnas sin documentar en el diccionario (", nombre_capa, "): ",
         paste(sin_documentar, collapse = ", "))
  }
  ausentes <- setdiff(dic$variable, names(datos))
  if (length(ausentes) > 0) {
    stop("Variables del diccionario ausentes en los datos (", nombre_capa, "): ",
         paste(ausentes, collapse = ", "))
  }
  filas <- lapply(dic$variable, function(v) {
    d <- filter(dic, variable == v)
    x <- datos[[v]]
    n_na <- sum(is.na(x))
    if (d$tipo == "numerico") {
      tipo_ok <- is.numeric(x)
      limites <- as.numeric(strsplit(d$valores_o_rango_esperado, " a ", fixed = TRUE)[[1]])
      fuera <- if (tipo_ok) sum(x < limites[1] | x > limites[2], na.rm = TRUE) else NA_integer_
      minimo <- if (tipo_ok && n_na < length(x)) min(x, na.rm = TRUE) else NA_real_
      maximo <- if (tipo_ok && n_na < length(x)) max(x, na.rm = TRUE) else NA_real_
    } else {
      tipo_ok <- is.character(x) || is.factor(x)
      minimo <- NA_real_
      maximo <- NA_real_
      if (v == "sample_id") {
        fuera <- sum(duplicated(x))
      } else {
        niveles <- trimws(strsplit(d$valores_o_rango_esperado, ";", fixed = TRUE)[[1]])
        fuera <- sum(!x[!is.na(x)] %in% niveles)
      }
    }
    tibble(
      variable = v, capa = capa, unidad = d$unidad, n = length(x), n_NA = n_na,
      min = minimo, max = maximo, rango_esperado = d$valores_o_rango_esperado,
      fuera_de_rango = fuera, tipo_correcto = tipo_ok
    )
  })
  bind_rows(filas) %>%
    mutate(estado = if_else(tipo_correcto & n_NA == 0 & fuera_de_rango == 0,
                            "OK", "REVISAR"))
}

validacion <- bind_rows(
  validar_capa(fisiologia, diccionario, "metadatos", metadatos, "metadatos"),
  validar_capa(fisiologia, diccionario, "fisiologia",
               setdiff(names(fisiologia), metadatos)),
  validar_capa(ionomica, diccionario, "ionomica",
               setdiff(names(ionomica), metadatos)),
  validar_capa(metabolomica, diccionario, "metabolomica",
               setdiff(names(metabolomica), metadatos))
)
# sample_id repetido en cualquiera de las tres capas
duplicados_sample_id <- sum(duplicated(fisiologia$sample_id)) +
  sum(duplicated(ionomica$sample_id)) + sum(duplicated(metabolomica$sample_id))

# Integración por sample_id (relación uno a uno)
integrado <- fisiologia %>%
  left_join(select(ionomica, -all_of(metadatos[-1])),
            by = "sample_id", relationship = "one-to-one") %>%
  left_join(select(metabolomica, -all_of(metadatos[-1])),
            by = "sample_id", relationship = "one-to-one")

columnas_medicion <- setdiff(names(integrado), c(metadatos, "tipo_dato"))
columnas_no_numericas <- columnas_medicion[
  !vapply(integrado[columnas_medicion], is.numeric, logical(1))
]
if (length(columnas_no_numericas) > 0) {
  stop("Las mediciones deben ser numéricas: ", paste(columnas_no_numericas, collapse = ", "))
}

dir.create(dir_salida, recursive = TRUE, showWarnings = FALSE)
dir.create(dir_figuras, recursive = TRUE, showWarnings = FALSE)
dir.create(dir_reportes, recursive = TRUE, showWarnings = FALSE)

# Informe de validación en Markdown
fmt_num <- function(x) ifelse(is.na(x), "-", format(x, trim = TRUE, drop0trailing = TRUE))
n_revisar <- sum(validacion$estado == "REVISAR")
tabla_md <- validacion %>%
  mutate(across(c(min, max), fmt_num)) %>%
  transmute(
    linea = paste0("| ", variable, " | ", capa, " | ", unidad, " | ", n, " | ", n_NA,
                   " | ", min, " | ", max, " | ", rango_esperado, " | ",
                   fuera_de_rango, " | ", estado, " |")
  )
writeLines(c(
  "# Validación de datos contra el diccionario",
  "",
  paste0("Fecha de ejecución: ", format(Sys.Date(), "%Y-%m-%d")),
  "",
  "Datos simulados. Referencia: `data/diccionario_datos.csv`.",
  "",
  paste0("- Variables validadas: ", nrow(validacion)),
  paste0("- Variables con estado REVISAR: ", n_revisar),
  paste0("- Valores faltantes en total: ", sum(validacion$n_NA)),
  paste0("- Valores fuera de rango o de niveles esperados: ",
         sum(validacion$fuera_de_rango, na.rm = TRUE)),
  paste0("- `sample_id` repetidos (suma de las tres capas): ", duplicados_sample_id),
  paste0("- Estado general: ", if (n_revisar == 0) "OK" else "REVISAR"),
  "",
  "Para variables de tipo factor, `fuera_de_rango` cuenta valores fuera de los niveles esperados; para `sample_id`, cuenta duplicados.",
  "",
  "| variable | capa | unidad | n | n_NA | min | max | rango esperado | fuera_de_rango | estado |",
  "|---|---|---|---|---|---|---|---|---|---|",
  tabla_md$linea
), file.path(dir_reportes, "validacion.md"), useBytes = FALSE)
write_csv(integrado, file.path(dir_salida, "dataset_integrado_simulado.csv"), na = "NA")

capas_variables <- data.frame(
  variable = c(
    setdiff(names(fisiologia), metadatos),
    setdiff(names(ionomica), metadatos),
    setdiff(names(metabolomica), c(metadatos, "tipo_dato"))
  ),
  layer = c(
    rep("Fisiología", length(setdiff(names(fisiologia), metadatos))),
    rep("Ionómica", length(setdiff(names(ionomica), metadatos))),
    rep("Metabolómica", length(setdiff(names(metabolomica), c(metadatos, "tipo_dato"))))
  )
)
datos_largos <- integrado %>%
  pivot_longer(all_of(columnas_medicion), names_to = "variable", values_to = "value") %>%
  left_join(capas_variables, by = "variable", relationship = "many-to-one")
write_csv(datos_largos, file.path(dir_salida, "dataset_largo_simulado.csv"), na = "NA")

conteo_diseno <- integrado %>% count(genotipo, tratamiento, name = "n_muestras")
resumen_faltantes <- datos_largos %>%
  group_by(layer, variable) %>%
  summarise(
    n_total = n(),
    n_missing = sum(is.na(value)),
    percent_missing = round(100 * n_missing / n_total, 1),
    .groups = "drop"
  ) %>%
  arrange(desc(n_missing), layer, variable)

# Resumen descriptivo por los grupos indicados
resumir_distribucion <- function(datos, grupos) {
  datos %>%
    group_by(across(all_of(grupos))) %>%
    summarise(
      n = sum(!is.na(value)),
      n_missing = sum(is.na(value)),
      mean = if (n > 0) mean(value, na.rm = TRUE) else NA_real_,
      sd = if (n > 1) sd(value, na.rm = TRUE) else NA_real_,
      median = if (n > 0) median(value, na.rm = TRUE) else NA_real_,
      q1 = if (n > 0) as.numeric(quantile(value, 0.25, na.rm = TRUE)) else NA_real_,
      q3 = if (n > 0) as.numeric(quantile(value, 0.75, na.rm = TRUE)) else NA_real_,
      .groups = "drop"
    ) %>%
    mutate(across(c(mean, sd, median, q1, q3), ~ round(.x, 2)))
}

resumen_tratamiento <- resumir_distribucion(
  datos_largos, c("layer", "variable", "tratamiento")
)
resumen_genotipo <- resumir_distribucion(
  datos_largos, c("layer", "variable", "tratamiento", "genotipo")
)
cambio_relativo <- datos_largos %>%
  group_by(layer, variable, tratamiento) %>%
  summarise(
    mean = if (all(is.na(value))) NA_real_ else mean(value, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  pivot_wider(names_from = tratamiento, values_from = mean) %>%
  mutate(percent_change = if_else(
    is.na(Control) | is.na(Calor) | Control == 0,
    NA_real_,
    round(100 * (Calor - Control) / Control, 1)
  )) %>%
  mutate(across(c(Control, Calor), ~ round(.x, 2)))

spearman_o_na <- function(x, y) {
  complete <- complete.cases(x, y)
  if (sum(complete) < 3 || n_distinct(x[complete]) < 2 ||
      n_distinct(y[complete]) < 2) return(NA_real_)
  round(cor(x[complete], y[complete], method = "spearman"), 2)
}
correlaciones <- integrado %>%
  group_by(tratamiento) %>%
  summarise(
    n_A_K = sum(complete.cases(A_net, K_mg_g)),
    rho_A_K = spearman_o_na(A_net, K_mg_g),
    n_A_Prolina = sum(complete.cases(A_net, Prolina)),
    rho_A_Prolina = spearman_o_na(A_net, Prolina),
    .groups = "drop"
  )

write_csv(conteo_diseno, file.path(dir_reportes, "eda_diseno.csv"))
write_csv(resumen_faltantes, file.path(dir_reportes, "eda_faltantes.csv"))
write_csv(resumen_tratamiento, file.path(dir_reportes, "eda_resumen_tratamiento.csv"), na = "NA")
write_csv(resumen_genotipo, file.path(dir_reportes, "eda_resumen_genotipo.csv"), na = "NA")
write_csv(cambio_relativo, file.path(dir_reportes, "eda_cambios_relativos.csv"), na = "NA")
write_csv(correlaciones, file.path(dir_reportes, "eda_correlaciones.csv"), na = "NA")

cat("DATOS SIMULADOS: solo EDA descriptivo\n")
cat("Datos integrados:", nrow(integrado), "muestras,", ncol(integrado),
    "columnas,", length(columnas_medicion), "mediciones numéricas\n")
cat("Muestras por genotipo y tratamiento:\n")
print(conteo_diseno, n = Inf)
cat("Valores faltantes en la tabla completa:", sum(is.na(integrado)), "\n")
cat("Estadísticos descriptivos seleccionados por tratamiento:\n")
print(
  resumen_tratamiento %>%
    filter(variable %in% c("A_net", "K_mg_g", "Prolina")) %>%
    select(variable, tratamiento, n, mean, sd, median, q1, q3),
  n = Inf
)
cat("Correlaciones de Spearman exploratorias dentro de cada tratamiento:\n")
print(correlaciones)
cat("Cambios relativos seleccionados (calor frente a control):\n")
print(cambio_relativo %>%
        filter(variable %in% c("A_net", "K_mg_g", "Prolina")) %>%
        select(variable, Control, Calor, percent_change))

etiquetas_clave <- c(
  A_net = "Fotosíntesis (umol CO2 m-2 s-1)",
  K_mg_g = "Potasio (mg/g)",
  Prolina = "Prolina (AU)"
)
colores_tratamiento <- c(Control = "#0072B2", Calor = "#D55E00")
datos_clave <- datos_largos %>%
  filter(variable %in% names(etiquetas_clave)) %>%
  mutate(
    variable = factor(variable, levels = names(etiquetas_clave), labels = unname(etiquetas_clave)),
    tratamiento = factor(tratamiento, levels = c("Control", "Calor"))
  )

grafico_distribucion <- ggplot(
  datos_clave, aes(x = genotipo, y = value, fill = tratamiento)
) +
  geom_boxplot(width = 0.6, alpha = 0.75, outlier.shape = NA,
               position = position_dodge(width = 0.75)) +
  geom_point(shape = 21, color = "#222222", size = 1.5, alpha = 0.8,
             position = position_jitterdodge(jitter.width = 0.08,
                                             dodge.width = 0.75, seed = 42)) +
  facet_wrap(~ variable, scales = "free_y", nrow = 1) +
  scale_fill_manual(values = colores_tratamiento) +
  labs(
    title = "Tres capas bajo control y calor",
    subtitle = "Datos simulados; puntos = muestras individuales",
    x = "Genotipo", y = "Valor (unidad indicada en cada panel)",
    fill = "Tratamiento",
    caption = "Cajas: mediana y rango intercuartílico; cuatro muestras por combinación."
  ) +
  theme_bw(base_size = 11) +
  theme(legend.position = "bottom", panel.grid.minor = element_blank(),
        plot.title = element_text(face = "bold"))

grafico_relacion <- ggplot(
  integrado %>%
    mutate(tratamiento = factor(tratamiento, levels = c("Control", "Calor"))),
  aes(x = A_net, y = Prolina, color = genotipo)
) +
  geom_point(size = 2.4, alpha = 0.85) +
  facet_wrap(~ tratamiento) +
  scale_color_manual(values = c(
    G1 = "#0072B2", G2 = "#D55E00", G3 = "#009E73",
    G4 = "#CC79A7", G5 = "#E69F00"
  )) +
  labs(
    title = "Fotosíntesis y prolina por tratamiento",
    subtitle = "Relación exploratoria entre fisiología y metabolómica",
    x = "Fotosíntesis neta (umol CO2 m-2 s-1)",
    y = "Prolina (abundancia relativa, AU)",
    color = "Genotipo",
    caption = "Datos simulados; la asociación no implica causalidad."
  ) +
  theme_bw(base_size = 11) +
  theme(legend.position = "bottom", panel.grid.minor = element_blank(),
        plot.title = element_text(face = "bold"))


# Cambio porcentual Calor vs Control por genotipo y variable (mapa de calor)
orden_capas <- c("Fisiología", "Ionómica", "Metabolómica")
cambio_genotipo <- datos_largos %>%
  group_by(layer, variable, genotipo, tratamiento) %>%
  summarise(mean = mean(value, na.rm = TRUE), .groups = "drop") %>%
  pivot_wider(names_from = tratamiento, values_from = mean) %>%
  mutate(percent_change = if_else(Control == 0, NA_real_,
                                  100 * (Calor - Control) / Control)) %>%
  mutate(across(c(Control, Calor), ~ round(.x, 2)),
         percent_change = round(percent_change, 1)) %>%
  arrange(factor(layer, levels = orden_capas),
          match(variable, columnas_medicion), genotipo)
write_csv(cambio_genotipo, file.path(dir_reportes, "eda_cambio_genotipo.csv"), na = "NA")

datos_mapa <- cambio_genotipo %>%
  mutate(layer = factor(layer, levels = orden_capas),
         variable = factor(variable, levels = rev(columnas_medicion)))
limite_color <- max(abs(datos_mapa$percent_change), na.rm = TRUE)
grafico_mapa <- ggplot(datos_mapa, aes(x = genotipo, y = variable, fill = percent_change)) +
  geom_tile(color = "white", linewidth = 0.5) +
  geom_text(aes(label = round(percent_change, 0)), size = 3) +
  facet_grid(layer ~ ., scales = "free_y", space = "free") +
  scale_fill_gradient2(
    low = "#0072B2", mid = "white", high = "#D55E00", midpoint = 0,
    limits = c(-limite_color, limite_color), name = "Cambio (%)"
  ) +
  labs(
    title = "El calor afecta más a G2, G4 y G5; rafinosa y prolina suben en todos los genotipos",
    subtitle = "Cambio porcentual de la media bajo calor frente a control, por genotipo y variable",
    x = "Genotipo", y = NULL,
    caption = "Fuente: datos simulados (este repositorio). n = 4 por celda; azul = disminuye, naranja = aumenta."
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid = element_blank(), legend.position = "right",
        plot.title = element_text(face = "bold", size = 11),
        plot.title.position = "plot",
        strip.text.y = element_text(angle = 0, face = "bold"))
alto_mapa <- 2 + 0.3 * length(columnas_medicion)

ggsave(file.path(dir_figuras, "eda_multicapa.pdf"), grafico_distribucion,
       width = 11, height = 4.8, units = "in", device = grDevices::pdf,
       timestamp = FALSE)
ggsave(file.path(dir_figuras, "eda_relacion_capas.pdf"), grafico_relacion,
       width = 8, height = 4.8, units = "in", device = grDevices::pdf,
       timestamp = FALSE)
ggsave(file.path(dir_figuras, "eda_mapa_calor_cambio.pdf"), grafico_mapa,
       width = 8, height = alto_mapa, units = "in", device = grDevices::pdf,
       timestamp = FALSE)

# Copias PNG para mostrarlas en el README (GitHub no muestra PDF inline)
ggsave(file.path(dir_figuras, "eda_multicapa.png"), grafico_distribucion,
       width = 11, height = 4.8, units = "in", dpi = 200)
ggsave(file.path(dir_figuras, "eda_relacion_capas.png"), grafico_relacion,
       width = 8, height = 4.8, units = "in", dpi = 200)
ggsave(file.path(dir_figuras, "eda_mapa_calor_cambio.png"), grafico_mapa,
       width = 8, height = alto_mapa, units = "in", dpi = 300)
cat("Validación escrita en reports/validacion.md:", n_revisar, "variables en REVISAR\n")
cat("Figuras guardadas en figures/ (PDF y PNG)\n")
