#!/bin/bash
#
# ============================================================================
# Script: run_tbss_FA_and_MD.sh
#
# 📌 Purpose:
# Runs the full TBSS pipeline on FA maps and then applies FA-derived
# registration and skeleton projection to MD maps using FSL's `tbss_non_FA`.
# Designed for the mTBI-Predict study, harmonising across multiple sites.
#
# 📁 Input:
# - FA images: derivatives/TBSS_analysis/FA/
# - MD images: derivatives/TBSS_analysis/MD/ (from dtifit)
#
# 📤 Output:
# - FA TBSS:    derivatives/TBSS_analysis/FA/stats/
# - MD TBSS:    derivatives/TBSS_analysis/stats/all_MD_skeletonised.nii.gz
#
# ⚙️ Dependencies:
# - FSL ≥ 6.0.6
# ============================================================================

STARTTIME=$(date +%s)
echo "Running on $(hostname)"
echo "Started at: $(date +%F_%T)"

cd derivatives/TBSS_analysis || { echo "TBSS_analysis directory not found."; exit 1; }

# ----------------------------------------------------------------------------
# Step 1: Run TBSS on FA
# ----------------------------------------------------------------------------
echo "🔧 Step 1: Running TBSS on FA maps..."

cd FA || { echo "FA folder not found."; exit 1; }

tbss_1_preproc *.nii.gz
tbss_2_reg -T
tbss_3_postreg -S
tbss_4_prestats 0.25

echo "TBSS on FA complete."
cd ..

# ----------------------------------------------------------------------------
# Step 2: Run TBSS projection for MD maps
# ----------------------------------------------------------------------------
echo "Step 2: Preparing MD maps and running tbss_non_FA..."

cd MD || { echo "MD folder not found."; exit 1; }

# Rename MD maps to look like FA maps
for file in *_MD.nii.gz; do
  base=$(basename "$file")
  new_name="${base/_MD.nii.gz/_FA.nii.gz}"
  cp "$file" "$new_name"
done

cd ..

# Run TBSS projection using FA-based registration
tbss_non_FA MD

# ----------------------------------------------------------------------------
# Wrap-up
# ----------------------------------------------------------------------------
ENDTIME=$(date +%s)
Total_time=$(echo "scale=2; ($ENDTIME - $STARTTIME)/3600.0" | bc -l)
echo "🎉 TBSS FA + MD analysis completed after ${Total_time} hours"
