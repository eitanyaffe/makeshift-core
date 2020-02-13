TARGET1_DONE?=$(MODULE1_DIR)/.done_step1
$(TARGET1_DONE):
	$(call _start,$(MODULE1_DIR))
	ls -l | head -n $(N_LINES) > $(MODULE1_STEP1)
	$(_end_touch)
target1: $(TARGET1_DONE)

TARGET2_DONE?=$(MODULE1_DIR)/.done_step2
$(TARGET2_DONE): $(TARGET1_DONE)
	$(_start)
	wc $(MODULE1_STEP1) > $(MODULE1_STEP2)
	$(_end_touch)
target2: $(TARGET2_DONE)
