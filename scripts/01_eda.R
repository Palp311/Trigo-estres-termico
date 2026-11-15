# Análisis exploratorio de datos simulados de fisiología, ionómica y metabolómica.
paquetes_requeridos <- c("dplyr", "tidyr", "ggplot2", "readr")
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
})

# Rutas y metadatos comunes a las tres capas
dir_datos <- file.path("data", "raw")
dir_salida <- file.path("data", "processed")
dir_figuras <- "figures"
dir_reportes <- "reports"
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

ggsave(file.path(dir_figuras, "eda_multicapa.pdf"), grafico_distribucion,
       width = 11, height = 4.8, units = "in", device = grDevices::pdf,
       timestamp = FALSE)
ggsave(file.path(dir_figuras, "eda_relacion_capas.pdf"), grafico_relacion,
       width = 8, height = 4.8, units = "in", device = grDevices::pdf,
       timestamp = FALSE)

# Copias PNG para mostrarlas en el README (GitHub no muestra PDF inline)
ggsave(file.path(dir_figuras, "eda_multicapa.png"), grafico_distribucion,
       width = 11, height = 4.8, units = "in", dpi = 200)
ggsave(file.path(dir_figuras, "eda_relacion_capas.png"), grafico_relacion,
       width = 8, height = 4.8, units = "in", dpi = 200)
cat("Figuras guardadas en figures/ (PDF y PNG)\n")
