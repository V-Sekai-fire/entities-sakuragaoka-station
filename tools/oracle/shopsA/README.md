# shopsA oracle comparison

detail.mjs prints the original's per-shop mesh, group, instance and collider counts; cmp.sh diffs them
against tools/_shopsA_detail.gd. They run in a copy of the original (tools/oracle/shot.mjs's checkout)
with shopsA-only.patch applied, which adds the SHOPS_ONLY filter. cmp.sh's paths are the scratch
worktrees it was written in.
