#!/bin/bash
# -----------------------------------------------------------------------------
# Script: extract_FA_MD_global_and_ROIs.sh
#
# 📌 Purpose:
# Extracts global and regional mean FA and MD values from TBSS skeleton maps
# using the JHU white matter atlas (48 ROIs), for the mTBI-Predict study.
#
# 📁 Input (in derivatives/TBSS_analysis):
# - all_FA_skeletonised.nii.gz
# - all_MD_skeletonised.nii.gz
# - mean_FA_skeleton_mask.nii.gz
# - JHU-ICBM-labels-1mm.nii.gz (atlas from FSL)
#
# 📤 Output:
# - global_wm_FA.txt, global_wm_MD.txt
# - ROI_XX_FA.txt, ROI_XX_MD.txt
# - FA_all.txt, MD_all.txt
#
# ⚙️ Dependencies:
# - FSL ≥ 6.0.6
# ============================================================================

STARTTIME=$(date +%s)
echo "Running on $(hostname)"
echo "Started at: $(date +%F_%T)"

# === Set working directory ===
tbss_dir="derivatives/TBSS_analysis"
cd "$tbss_dir" || { echo "Cannot find $tbss_dir"; exit 1; }

# === File paths ===
FA_IMAGE="all_FA_skeletonised.nii.gz"
MD_IMAGE="all_MD_skeletonised.nii.gz"
SKELETON_MASK="mean_FA_skeleton_mask.nii.gz"
JHU_ATLAS="$FSLDIR/data/atlases/JHU/JHU-ICBM-labels-1mm.nii.gz"

# === Global Mean Extraction ===
echo "Calculating global mean FA and MD..."

fslmaths $FA_IMAGE -mul $SKELETON_MASK global_wm_FA.nii.gz
fslmaths $MD_IMAGE -mul $SKELETON_MASK global_wm_MD.nii.gz

fslstats -t global_wm_FA.nii.gz -M > global_wm_FA.txt
fslstats -t global_wm_MD.nii.gz -M > global_wm_MD.txt

echo "Global values saved to global_wm_FA.txt and global_wm_MD.txt"

# === ROI-based Extraction (48 regions from JHU) ===
echo "Extracting ROI-wise mean FA and MD values using JHU atlas..."

for i in {1..48}; do
  roi_bin="ROI_${i}.nii.gz"
  roi_mul_FA="ROI_${i}_mul_FA.nii.gz"
  roi_mul_MD="ROI_${i}_mul_MD.nii.gz"

  # Create binary mask for ROI
  fslmaths $atlas_path -thr $i -uthr $i -bin $roi_bin

  # Multiply skeleton maps with ROI
  fslmaths $FA_IMAGE -mul $roi_bin $roi_mul_FA
  fslmaths $MD_IMAGE -mul $roi_bin $roi_mul_MD

  # Extract mean across timepoints
  fslstats -t $roi_mul_FA -M >> ROI_${i}_FA.txt
  fslstats -t $roi_mul_MD -M >> ROI_${i}_MD.txt
done

echo "Collating all ROI values..."

# Combine per-ROI results into summary tables
for FILE in ROI_*_FA.txt; do echo -n -e "$FILE\t"; cat "$FILE"; done > FA_all.txt
for FILE in ROI_*_MD.txt; do echo -n -e "$FILE\t"; cat "$FILE"; done > MD_all.txt

echo "Summary tables: FA_all.txt and MD_all.txt"

# === Wrap up ===
ENDTIME=$(date +%s)
Total_time=$(echo "scale=2; ($ENDTIME - $STARTTIME)/3600.0" | bc -l)
echo "Extraction complete after ${Total_time} hours"
