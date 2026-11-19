# =============================================================================
# run_all.R — Run the full analysis
# -----------------------------------------------------------------------------
# Open the project through its .Rproj file, then run this script.
# All scripts run in order, in the same R session.
# =============================================================================

source("R/setup.R")

message("\n1/4 Preparing the data...")
source("R/01_prepare_data.R")

message("\n2/4 Analysing framing...")
source("R/02_analyze_framing.R")

message("\n3/4 Analysing the text...")
source("R/03_analyze_text.R")

message("\n4/4 Creating figures...")
source("R/04_create_figures.R")

message("\nDone. Tables are in outputs/tables/ and figures in outputs/figures/.")
