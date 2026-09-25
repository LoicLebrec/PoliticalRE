# Builds figures/cumulative_parks_evolution.png (paper fig:parks_evolution):
# cumulative number of commissioned wind farms in France, 2000-2025, with the
# three pre-treatment election years (2008, 2014, 2020) marked.
#
# A park counts from the year of its date_mise_en_service in Parc.csv,
# whatever its current status (a since-decommissioned park still counts as
# having been commissioned) -- same commissioning-date definition as
# build_panel.R. One point per distinct id_parc (earliest commissioning year
# if a park appears on several rows). National scope, not restricted to the
# rural analytic sample. Reproduces the figure previously shipped in the
# paper, which had no surviving script, exactly (242 / 718 / 1,288 / 1,658
# parks at 2008 / 2014 / 2020 / 2025).
#
# Usage (from the repo root): Rscript code/descriptive/build_parks_evolution.R

suppressPackageStartupMessages({
  library(dplyr); library(ggplot2)
})

PROJECT <- Sys.getenv("POLITICALRE_ROOT", unset = ".")
FIG     <- file.path(PROJECT, "code/descriptive/figures")
dir.create(FIG, showWarnings = FALSE, recursive = TRUE)

YEARS    <- 2000:2025
ELECTION <- c(2008, 2014, 2020)

parc <- read.csv(file.path(PROJECT, "data/parceolien/Parc.csv"),
                 check.names = FALSE, stringsAsFactors = FALSE,
                 colClasses = c(id_parc = "character"))

first_year <- parc %>%
  mutate(y = as.integer(substr(date_mise_en_service, 1, 4))) %>%
  filter(!is.na(y), y >= 1990) %>%
  group_by(id_parc) %>%
  summarise(y = min(y), .groups = "drop")

cum <- tibble(year = YEARS) %>%
  mutate(n = sapply(year, function(Y) sum(first_year$y <= Y)))

cat("Cumulative commissioned parks:\n")
print(cum %>% filter(year %in% c(ELECTION, max(YEARS))))

p <- ggplot(cum, aes(year, n)) +
  geom_area(fill = "#2878d6", alpha = 0.15) +
  geom_vline(xintercept = ELECTION, linetype = "dashed", colour = "grey45") +
  annotate("text", x = ELECTION - 0.25, y = max(cum$n) * 0.93, label = ELECTION,
           angle = 90, colour = "grey40", size = 3.2) +
  geom_line(colour = "#2878d6", linewidth = 1.1) +
  geom_point(colour = "#2878d6", size = 1.6) +
  scale_x_continuous(breaks = seq(2000, 2025, 5)) +
  labs(title = sprintf("Growth of commissioned wind capacity in France, %d-%d", min(YEARS), max(YEARS)),
       x = NULL, y = "Cumulative commissioned wind farms") +
  theme_bw(base_size = 12) +
  theme(plot.title = element_text(face = "bold"), panel.grid.minor = element_blank())

ggsave(file.path(FIG, "cumulative_parks_evolution.png"), p, width = 8, height = 4.5, dpi = 200)
cat(sprintf("Saved -> %s\n", file.path(FIG, "cumulative_parks_evolution.png")))
