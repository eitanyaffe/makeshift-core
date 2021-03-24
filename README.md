# Makeshift: a gnu-make workflow extension 
Makeshift is a workflow infrastructure based on gnu-make, developed by Eitan Yaffe (eitan.yaffe@gmail.com). It defines makefile functions that allow to define steps (bash calls) that are orgazined within makeshift modules. A key feature of makeshift is the ability to rapidly customize any call parameter.

Installation
------------

Get the repository from github:
```
%> git clone https://github.com/eitanyaffe/makeshift-core
```

Set the MAKESHIFT_ROOT environment variable to the parent of the makeshift-core directory. Can be done in the .bashrc file:
```
export MAKESHIFT_ROOT=/path/to/parent_dir/of/makeshift-core
```

Usage example
-------------

To run on a template example cd into the example/basic directory and run:
```
%> make p_module1
```

Template code
-------------

```
include $(MAKESHIFT_ROOT)/makeshift-core/makeshift.mk

#####################################################################################################
# config file
#####################################################################################################

c?=config/default.cfg
include $(c)
$(call _set_user_title,config: $(c))

#####################################################################################################
# modules
#####################################################################################################

# global parameters
$(call _module,global.mk)

# include module1
$(call _module,md/module1/module1_int.mk)

# default module
m?=module1
$(call _active_module,$(m))

#####################################################################################################
# main pipeline rules
#####################################################################################################

p_module1:
	@$(MAKE) m=module1 target2
```
