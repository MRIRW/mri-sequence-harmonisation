#!/bin/bash

# ============================================================================
# Script: run_freesurfer_t1.sh
#
# 📌 Purpose:
# Runs Freesurfer recon-all on a BIDS-formatted T1w image located in the 
# anat/ folder of a subject-session. Output goes into derivatives.
#
# 💡 Study:
# Designed for mTBI-Predict study. Processes T1 anatomical data to generate
# cortical thickness and segmentation outputs using FreeSurfer.
#
# 📁 Input:
# - T1w image: bids/<sub>/<ses>/anat/<sub>_<ses>_T1w.nii[.gz]
#
# 📤 Output:
# - Reoriented T1w: derivatives/cortical_thickness_analysis/<sub>/<ses>/
# - FreeSurfer recon-all: derivatives/cortical_thickness_analysis/freesurfer/
#
# ⚙️ Dependencies:
# - FSL, FreeSurfer (modules must be loaded)
# ============================================================================

STARTTIME=$(date +%s)
echo "Running on $(hostname)"
echo "Started at: $(date +%F_%T)"

# === Load relevant modules ===
module load fsl
module load freesurfer

# === Set subject and session IDs ===
sub="sub-0001"
ses="ses-01A"
root_dir=$(pwd)

# === Define input T1 path from BIDS ===
t1_in="${root_dir}/bids/${sub}/${ses}/anat/${sub}_${ses}_T1w.nii"
if [[ ! -f "$t1_in" ]]; then
  t1_in="${t1_in}.gz"
fi

if [[ ! -f "$t1_in" ]]; then
  echo "T1 image not found at: $t1_in"
  exit 1
fi

# === Prepare derivatives output path ===
deriv_dir="${root_dir}/derivatives/cortical_thickness_analysis/${sub}/${ses}"
mkdir -p "$deriv_dir"

t1_std="${deriv_dir}/${sub}_${ses}_T1w_reoriented.nii.gz"
fslreorient2std "$t1_in" "$t1_std"

# === Run FreeSurfer recon-all ===
export SUBJECTS_DIR="${root_dir}/derivatives/cortical_thickness_analysis/freesurfer"
mkdir -p "$SUBJECTS_DIR"

recon-all -i "$t1_std" -subject "${sub}_${ses}" -sd "$SUBJECTS_DIR" -all

# === Wrap up ===
echo "recon-all complete for $sub $ses"
ENDTIME=$(date +%s)
Total_time=$(echo "scale=2; ($ENDTIME - $STARTTIME)/3600.0" | bc -l)
echo "Finished at $(date +%F_%T) after ${Total_time} hours"
