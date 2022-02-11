#####################################################################################################
#####################################################################################################
# PRIVATE
#####################################################################################################
#####################################################################################################

# allow to force root makefile
MMAKE:=$(MAKE) -f $(MROOT)

_version:=1.01

_info_active=$(if $(findstring $(mname),$1), (active))
_info_file=$(_$1_file)
_info_units=$(_$1_units)
_info_preqs=$(_$1_preqs)
_info_preqs_var=$(_$1_preqs_var)

_info_sep=--------------------------------------------------------------------------------
_step_sep=*-------*-------*-------*-------*-------*-------*-------*-------*-------*------*
_all_sep =-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*

define _info_module
echo $(_info_sep)
echo "module: $1$(call _info_active,$1)"
echo "source file: $(call _info_file,$1)"
echo "units: $(if $(_$1_units),$(call _info_units,$1),NA)"
echo "required modules: $(if $(_$1_preqs),$(call _info_preqs,$1),NA)"
echo "required variables: $(if $(_$1_preqs_var),$(call _info_preqs_var,$1),NA)"
endef


#####################################################################################################
# helper defs
#####################################################################################################

__space :=
__space +=
__comma := ,

#####################################################################################################
# gloabl makeshift variables
#####################################################################################################

# makeshift directory
_dir:=$(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# module path
_module_dir=$(_$(mname)_path)

# units
_units=$(_$(mname)_units)

# module pre-requisites
_preqs=$(_$(mname)_preqs)
_preqs_var=$(_$(mname)_preqs_var)

#####################################################################################################
# utility internal functions
#####################################################################################################

# working in docker we stop using the hostname
_binary_suffix=general
# _binary_suffix=$(shell hostname)

define bin_rule
$(_md)/bin/%: $(_md)/cpp/%.cpp
	mkdir -p $$(@D)
	g++ $$^ -O2 -o $$@ -Wall -Wno-write-strings -std=c++0x
$(_md)/bin.$(_binary_suffix)/%: $(_md)/cpp/%.cpp
	mkdir -p $$(@D)
	g++ $$^ -O2 -o $$@ -Wall -Wno-write-strings -std=c++0x
endef

define bin_rule2
$(_md)/bin/$1: $(_md)/cpp/$(addsuffix .cpp,$1) $2
	mkdir -p $$(@D)
	g++ $$^ -O2 -o $$@ -Wall -Wno-write-strings -std=c++0x $3
$(_md)/bin.$(_binary_suffix)/$1: $(_md)/cpp/$(addsuffix .cpp,$1) $2
	mkdir -p $$(@D)
	g++ $$^ -O2 -o $$@ -Wall -Wno-write-strings -std=c++0x $3
endef

define bin_rule3
$(BIN_DIR)/$m/$1: $(_md)/cpp/$(addsuffix .cpp,$1) $2
	mkdir -p $$(@D)
	g++ $$^ -O2 -o $$@ -Wall -Wno-write-strings -std=c++0x $3
endef

define bin_rule4
/tmp/$1: $(_md)/cpp/$(addsuffix .cpp,$1) $2
	g++ $$^ -O2 -o $$@ -Wall -Wno-write-strings -std=c++0x $3
endef

define bin_rule_boost
$(_md)/bin/$1: $(_md)/cpp/$(addsuffix .cpp,$1) $2
	mkdir -p $$(@D)
	g++ $$^ -I $(BOOST_DIR) -O2 -o $$@ -Wall -Wno-write-strings -std=c++0x $3
$(_md)/bin.$(_binary_suffix)/$1: $(_md)/cpp/$(addsuffix .cpp,$1) $2
	mkdir -p $$(@D)
	g++ $$^ -I $(BOOST_DIR) -O2 -o $$@ -Wall -Wno-write-strings -std=c++0x $3
endef

define bin_rule_debug
$(_md)/bin/$1: $(_md)/cpp/$(addsuffix .cpp,$1) $2
	mkdir -p $$(@D)
	g++ $$^ -g -O0 -o $$@ -Wall -Wno-write-strings -std=c++0x $3
$(_md)/bin.$(_binary_suffix)/$1: $(_md)/cpp/$(addsuffix .cpp,$1) $2
	mkdir -p $$(@D)
	g++ $$^ -g -O0 -o $$@ -Wall -Wno-write-strings -std=c++0x $3
endef

# verify variable defined
__check_defined=\
$(if $(value $1),,$(error Undefined parameter $1$(if $(value 2), ($(strip $2)))))

# verify file exists
_file_exists=\
$(if $(wildcard $1),, $(error file not found: $1))

# verify dir exists
_dir_exists=\
$(if $(wildcard $1),, $(error directory not found: $1))

_assert_module_exists=$(if $(findstring $1,$(__modules)),,$(error module $1 not defined))
_assert_module_not_exists=$(if $(findstring $1,$(__modules)),$(error module $1 already defined))

_module_pr=$(if $(findstring $1,$(__modules)),,$(error pre-requisite module $1 of module $(mname) not defined))
_var_pr=$(if $($1),,$(error pre-requisite variable $(value 1) of module $(mname) not defined))

_get_module_dir=$(_$(1)_path)

_assert_class_exists=$(if $(findstring $1,$(__classes)),,$(error class $1 not defined))
_assert_class_not_exists=$(if $(findstring $1,$(__classes)),$(error class $1 already defined))
_assert_instance_exists=$(if $(findstring $2,$(__class_$1)),,$(error class instance $2 not defined in class $2))
_assert_instance_not_exists=$(if $(findstring $2,$(__class_$1)),$(error class instance $2 already defined in class $1))

_assert_target_exists=$(if $(findstring $2,$(call _get_targets,$1)),,$(error target $2 not defined in module $1))
_assert_target_not_exists=$(if $(findstring $2,$(call _get_targets,$1)),$(error target $2 not defined in module $1))

_set_units=$(eval _$1_units:=$2)
_set_path=$(eval _$1_path:=$2)
_set_file=$(eval _$1_file:=$2)
_set_preqs=$(eval _$1_preqs:=$2)
_set_preqs_var=$(eval _$1_preqs_var:=$2)

# 1: module, 2: target, 3: desc
_set_target=$(eval _$1_targets+=$2) $(eval _$1_target_$2:=$3)
_get_targets=$(_$1_targets)
_get_target=$(_$1_target_$2)

# load unit makefile
load_unit=\
$(call _file_exists, $1)\
$(eval include $1)

# is a dry run?
_dry=$(findstring n,$(filter-out --%,$(MAKEFLAGS)))

ifeq ($(_dry),)

# real

# rsync is done in two steps, to avoid uploading .done files before the directory content
ifdef GCP_RSYNC_SRC_VAR
define __rsync
@echo Delocalizing $(GCP_RSYNC_SRC_VAR) && \
gsutil -mq rsync -r -x ".*\.done.*|.*\.dsub.*" $($(GCP_RSYNC_SRC_VAR)) $(GCP_RSYNC_TARGET_BUCKET) && \
sleep 10s && \
gsutil -mq rsync -r -x ".*\.dsub.*" $($(GCP_RSYNC_SRC_VAR)) $(GCP_RSYNC_TARGET_BUCKET)
endef
else
endif

define __start
@echo "START: $@"
$(if $1,mkdir -p $1)
endef

define __end
$(__rsync)
@echo "END: $@"
@echo $(_step_sep)
endef

define __end_touch
@touch $@
$(__rsync)
@echo "END: $@"
@echo $(_step_sep)
endef

else

# dry

define __start
$(_step_sep)
START: $@
$(if $1,mkdir -p $1)
endef

__end=END: $@
__end_touch=END touch: $@

endif

# target definitions
.SILENT .PHONY: do info skip clean redo modules help

.DELETE_ON_ERROR:

#####################################################################################################
# general functions
#####################################################################################################

# 1: A list of variables Vs
# 2: A a list of items Is
# 3: A target T
# Prepare T for each item I of Is, while setting all variables of Vs to be V=V_I
_loop_make=$(foreach I,$2,\
		$(foreach V,$(addprefix $(I)_,$1),$(call $(call _assert,$(V))))\
		$(foreach V,$1,$(eval $(V)=$($(I)_$(V))))\
		$(MAKE) $3 $(join $(addsuffix =,$1),$(foreach V,$(addprefix $(I)_,$1),$($(V)))); $(ASSERT);)

# 1: A list of variables Vs
# 2: an item I
_loop_set=$(foreach V,$(addprefix $2_,$1),$(call $(call _assert,$(V))))\
	  $(foreach V,$1,$(eval export $(V)=$($2_$(V))))

_export_variable=$(foreach v,$1,$v=$($v))

CONTAINER_FLAG=/.dockerenv
# 1: config dir
# Sets external links, and project id
_set_config_dir=\
$(eval PROJECT_ID=$(shell cat $1/project_id)) \
$(foreach V,$(shell cat $1/path_vars | perl $(_dir)/parse_paths.pl $(CONTAINER_FLAG)),$(eval $V))

# 1: var name
# 2: table name
# 3: field
# _get_field=$(eval $(info hello) $1=$(shell perl $(_dir)/get_field.pl $2 $3))

define _get_field
`perl $(_dir)/get_field.pl $1 $2`
endef

define _get_params
`perl $(_dir)/table2params.pl $1 $2`
endef

#####################################################################################################
# config functions
#####################################################################################################

__config=\
$(call _file_exists,$1)\
$(eval include $1) \
$(eval _cd:=$(dir $(abspath $(lastword $(MAKEFILE_LIST))))) \
$(call _set_user_title,configuration dir: $(_cd))

#####################################################################################################
# module functions
#####################################################################################################

__module=\
$(call _file_exists,$1)\
$(eval include $1)

__active_module=\
$(if $1,\
$(if $(findstring $1,$(__modules)),,$(error module $1 not defined))\
$(call _assert_module_exists,$1)\
$(eval mname=$1)\
$(foreach preq,$(_preqs),$(call _module_pr,$(preq),$(mname)))\
$(foreach preq,$(_preqs_var),$(call _var_pr,$(preq),$(mname)))\
$(foreach unit,$(_units),$(call load_unit,$(_module_dir)/$(unit))))\
$(eval $(bin_rule))

# each module registers itself using this function
#  1: module name
#  2: unit makefiles
#  3: required modules
#  4: required variables
__register_module=\
$(call _assert_module_not_exists,$1)\
$(eval __modules+=$1)\
$(eval _mname:=$1)\
$(eval _$1_targets:=)\
$(call _set_units,$1,$2)\
$(call _set_preqs,$1,$3)\
$(call _set_preqs_var,$1,$4)\
$(call _set_path,$1,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))\
$(call _set_file,$1,$(lastword $(MAKEFILE_LIST)))\
$(foreach unit,$2,$(call _file_exists, $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/$2))

# register module target
#  1: module name
#  2: target
#  3: target description
__add_module_target=\
$(call _assert_module_exists,$1)\
$(call _assert_target_not_exists,$1,$2)\
$(call _set_target,$1,$2,$3)

# 1: module
__get_module_targets=\
$(call _assert_module_exists,$1)\
$(call _get_targets,$1)

#  1: module name
#  2: target
__get_module_target_desc=\
$(call _assert_module_exists,$1)\
$(call _assert_target_exists,$1,$2)\
$(call _get_target,$1,$2)

__step=\
$(if $1,\
$(eval _current_step_title:=$1)\
$(eval _current_step_rule:=$(if $($1),$($1),$1))\
$(eval _current_step_desc:=$(if $($1),$1: $($1),$1))\
$(eval .DEFAULT_GOAL:=do))

#####################################################################################################
# class functions
#####################################################################################################

# 1: class
_class_variable=__class_$1_vars

# code for nameless instances
# _class_index=__class_$1_index
# _class_index_increment=$($(call _class_index,$1):=$(shell echo $($(call _class_index,$1))+1|bc))$($(call _class_index,$1))

# 1: class
# 2: instance
_class_instance_variable_names=$(addprefix __class_$1_$2_,$(__class_$1_vars))

# 1: class
# 2: instance
# 3: variable
_class_instance_variable_name=$(addprefix __class_$1_$2_,$3)

# 1: class
# 2: instance
# 3: variable
_class_instance_variable_value=\
$(if $($($(call _class_instance_variable_name,$1,$2,$3))),$($($(call _class_instance_variable_name,$1,$2,$3))),$($(call _class_instance_variable_name,$1,$2,$3)))

# 1: class
# 2: instance
# 3: variable
# Same as _class_instance_variable_value, yet without expanding variables
_class_instance_variable_value_ne=\
$($(call _class_instance_variable_name,$1,$2,$3))

# 1: class
# 2: instance
_class_instance_variables=$(foreach V,\
		$(addprefix __class_$1_$2_,$(__class_$1_vars)),\
		$(if $($($(V))),$($($(V))),$($(V))))

#####################################################################################################
#####################################################################################################
# PUBLIC
#####################################################################################################
#####################################################################################################

#####################################################################################################
# class functions
#####################################################################################################

# define class type
# 1: class
# 2: variable names
_class=\
$(call _assert_class_not_exists,$1)\
$(eval __classes+=$1)\
$(eval $(call _class_variable,$1):=$2)

# define instance within class
# 1: class
# 2: instance
# 3: variable values. Upon activiation values are expanded if possible
_class_instance=\
$(call _assert_class_exists,$1)\
$(call _assert_instance_not_exists,$1,$2)\
$(eval __class_$1+=$2)\
$(foreach X,$(join $(addsuffix =,$(call _class_instance_variable_names,$1,$2)),$3),$(eval $X))

# define instance within class
# 1: class
# 2: instance
# 3: variable values. Values never expanded
_class_instance_ne=\
$(call _assert_class_exists,$1)\
$(call _assert_instance_not_exists,$1,$2)\
$(eval __class_$1+=$2)\
$(foreach X,$(join $(addsuffix =,$(call _class_instance_variable_names,$1,$2)),$3),$(info $X))

# get all instances of class
# 1: class
_class_get_instances=$(and $(call _assert_class_exists,$1),__class_$1)

# set current active instance of class
# 1: class
# 2: instance
_class_activate=\
$(call _assert_class_exists,$1)\
$(call _assert_instance_exists,$1,$2)\
$(info \#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#)\
$(info \# Set active instance: $1.$2)\
$(foreach X,$($(call _class_variable,$1)),$(eval export $X:=$(call _class_instance_variable_value,$1,$2,$X)))\
$(foreach X,$($(call _class_variable,$1)),$(info $X=$(call _class_instance_variable_value,$1,$2,$X)))\
$(info \#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#)

# retrieve string of activation
_class_activate_str=\
$(call _assert_class_exists,$1)\
$(call _assert_instance_exists,$1,$2)\
$(foreach X,$($(call _class_variable,$1)),$X=$(call _class_instance_variable_value,$1,$2,$X))

# set current active instance of class, without expanding variables and quitely
# 1: class
# 2: instance
_class_activate_quiet_ne=$(foreach X,$($(call _class_variable,$1)),$(eval export $X:=$(call _class_instance_variable_value_ne,$1,$2,$X)))

# get variable value across all instances
# 1: class
# 2: variable
_class_variable_list=$(strip $(foreach instance,$(__class_$1),$(call _class_activate_quiet_ne,$1,$(instance))$($2)))

# old:
# $(foreach X,$(join $(addsuffix :=,$($(call _class_variable,$1))),$(call _class_instance_variables,$1,$2)),$(eval export $X))

loop_step=$(MAKE) class_step t=$(1); $(ASSERT);

# 1: class
_class_get_instances=\
$(call _assert_class_exists,$1)\
$(__class_$1)

class_step:
	$(MAKE) $t $(call _class_activate_str,$(class),$(instance))

# make target t over all instances of class
class_loop:
	$(call _assert,t)
	@echo going over all instances of $(class): $(call _class_get_instances,$(class))
	$(call _assert_class_exists,$(class))
	$(foreach instance,$(__class_$(class)),\
	$(MAKE) class_step class=$(class) instance=$(instance); $(ASSERT);)

# alternative form sets the variables instead of passing them in the command line
class_step_alt:
	$(call _class_activate,$(class),$(instance))
	$(MAKE) $t
class_loop_alt:
	$(call _assert,t)
	@echo going over all instances of $(class): $(call _class_get_instances,$(class))
	$(call _assert_class_exists,$(class))
	$(foreach instance,$(__class_$(class)),\
	$(MAKE) class_step_alt class=$(class) instance=$(instance); $(ASSERT);)

# Example:
# $(call _class,point,X Y)             -> define class
# $(call _class_instance,point,p1,1 2) -> add instance p1
# $(call _class_instance,point,p2,3 Z) -> add instance p2
# Z=4                                  -> note Z is defined after instance p2
#                                         that's fine due to late expansion
# $(call _class_activate,point,p1)     -> sets global variables X=1 Y=2
# $(call _class_activate,point,p2)     -> sets global variables X=3 Y=4

.PHONY: class_step class_loop

#####################################################################################################
# module functions
#####################################################################################################

# add module using interface file
# 1: module filename
_module=$(call __module,$1)

# add module under current directory
# 1: module name
_module_local=$(call __module,md/$1/$1_int.mk)

# add module under MAKESHIFT_ROOT
# 1: module name
_module_root=$(call __module,$(MAKESHIFT_ROOT)/modules/$1/$(notdir $1)_int.mk)

# mark active module
_active_module=$(call __active_module,$1)

# each module registers itself using this function
#  1: module name
#  2: unit makefiles
#  3: required modules
#  4: required variables
_register_module=$(call __register_module,$1,$2,$3,$4)

# select step to perform
# 1: step to perform
_step=$(call __step,$1)

#####################################################################################################
# config functions
#####################################################################################################

# set config file
# 1: config filename
_config=$(call __config,$1)

# set config file under MAKESHIFT_ROOT
# 1: relative config filename
_config_root=$(call __config,$(MAKESHIFT_CONFIG)/$1/$(notdir $1)_cfg.mk)

#####################################################################################################
# module target
#####################################################################################################

# register module target
#  1: module name
#  2: target
#  3: target description
_add_module_target=$(call __add_module_target,$1,$2,$3)
_get_module_targets=$(call __get_module_targets,$1)
_get_module_target_desc=$(call __get_module_target_desc,$1,$2)

targets:
	@echo $m targets:
	@$(foreach t,$(call _get_module_targets,$m),echo " $t: $(call _get_target,$m,$t)";)
.PHONY: targets

#####################################################################################################
# general functions
#####################################################################################################

# verify variable defined and return value
_verify=$(if $(value $1),$1,$(error Undefined parameter $1$(if $(value 2), ($(strip $2)))))

# assert variables are defined
_assert=$(foreach 1,$1,$(__check_defined))

# place this macro on start
_start=$(__start)

# on end you can optionally touch the target ($@)
_end=$(__end)
_end_touch=$(__end_touch)

# module directory, for accessing module scripts
_md=$(_module_dir)

# wrapper script for easy access of R functions
_Rcall=Rscript $(_dir)/R_call.r $(_dir)
_R=$(_Rcall) $(_md)

# macro which saves stats into file
_time=/usr/bin/time -v -o $1/.stats$(if $2,_$2,)

# assert return code of last bash command, useful for foreach loops
define ASSERT
if [ $$? -ne 0 ]; then exit 1; fi
endef

# get directory of current file
cdir=$(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# set title
_set_user_title=$(eval _user_title:=$1)

# run a binary executable from the tmp dir
run_local=cp $1 /tmp/$(notdir $1) && chmod +x /tmp/$(notdir $1) && /tmp/$(notdir $1)

#####################################################################################################
# makeshift actions
#####################################################################################################

step_desc=module: $(mname), step: $(_current_step_title), unit rule: $(_current_step_rule)
sd=\# DONE: $(step_desc)

action_str=$(if $(_dry),\# ACTION do :: $(step_desc),@echo ACTION do :: $(step_desc))

define header_rule
	@echo \### MakeShift $(_version), active module: $(mname), $(_user_title) \###
endef

# perform current step
do:
	$(call action_str,ACTION do :: $(step_desc))
	$(if $(_dry),,@echo $(_all_sep))
	@$(MAKE) $(_current_step_rule)

# clean current step
clean:
	$(call action_str,ACTION clean :: $(step_desc))
	@rm -i $(_current_step_rule)

# redo current step
redo: clean do

# skip current step by touching target file
skip:
	$(call action_str,ACTION skip/touch :: $(step_desc))
	touch $(_current_step_rule)

# print step info
info:
	$(header_rule)
	@echo modules: $(__modules)
	@$(MAKE) targets

# perform t over all config files CFGS
cfgs:
	$(foreach C,$(CFGS),make c=$C $t; $(ASSERT);)

#####################################################################################################
# packaging
#####################################################################################################

package:
	@mkdir $(POUTDIR) -p
	tar -cvzf $(POUTDIR)/$(PTITLE).$(shell cat $(PVERSION)).tar.gz `find $(PPATHS) | grep -v svn | grep -v "~" | grep -v "\#"` --no-recursion

MS_VERSION=$(_dir)/.version
MS_FILES=$(_dir)
ms_package:
	@$(MAKE) package PPATHS="$(MS_FILES)" PVERSION=$(MS_VERSION) PTITLE=makeshift POUTDIR=versions

#####################################################################################################
# utility functions
#####################################################################################################

# re-evaluate variable $1 given other variables defined in $2
# example: $(call reval,SOME_DATASET_DIR,DATASET=$(DATASET1))
reval=$(shell $(MAKE) --no-print-directory print2 v=$1 $2 $(PAR_MAKEOVERRIDES))
reval2=$(shell $(MAKE) --no-print-directory print2 v=$1 $2)

# variable helper functions
print: ; @echo v=$($(v))
p: ; @echo v=$($(v))
print2: ; @echo $($(v))
ls: ; ls -lart $($(v))
head: ;	head $($(v))
tail: ;	tail $($(v))
cat: ;	cat $($(v))

# print work plan
plan:
	$(MAKE) $t -n PAR_TYPE=local
# clean plan, from scratch 
splan:
	@$(MAKE) $t -n PAR_TYPE=local | grep START

# print all modules
define module_rule
	echo "modules: $(__modules)"
	$(foreach module,$(__modules), $(call _info_module,$(module));)
endef

modules: ; $(module_rule)
# not much here for now
help:
	$(header_rule)
	@echo "Commands:"
	@echo "  help: bring step up-to-date"
	@echo "  do: bring step up-to-date"
	@echo "  clean: clean step"
	@echo "  redo: redo step"
	@echo "  skip: skip step by touching result"
	@echo "Example:"
	@echo "%> make m=module1 s=step1 step"

#####################################################################################################
# cloud related utils
#####################################################################################################

# try to copy twice, useful for gcsfuse bug 
cp2=cp $1 $2; if [ $$? -ne 0 ]; then cp $1 $2; fi

#####################################################################################################
# environment variables
#####################################################################################################

# _makeflags=$(shell echo $(MAKEFLAGS) | sed -n -e 's/^.*-- //p')

# # baseline makeshift variables after last module is registered
_track_vars_start=$(eval __mk_vars_base:=$(.VARIABLES))

# # capture variables, last line in pipeline makefile
#_track_vars_stop=\
#$(eval _mk_vars_final:=\
#$(filter-out _%,$(filter-out __mk_vars_base,$(filter-out $(__mk_vars_base),$(.VARIABLES))))) \
#$(eval _mk_vars_str:=$(foreach v,$(_mk_vars_final),$v=$($v)))
