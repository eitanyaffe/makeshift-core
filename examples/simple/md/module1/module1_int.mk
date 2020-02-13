#####################################################################################################
# register module
#####################################################################################################

units=sub_module_a.mk
$(call _register_module,module1,$(units),,)

#####################################################################################################
# module parameters
#####################################################################################################

MODULE1_DIR?=$(SAMPLE_DIR)/module1

# step 1
N_LINES?=3
MODULE1_STEP1?=$(MODULE1_DIR)/step1

# step2
MODULE1_STEP2?=$(MODULE1_DIR)/step2
