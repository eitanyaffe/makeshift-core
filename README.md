# Makeshift: a workflow/pipeline infrastructure based on gnu-make
Makeshift is a workflow infrastructure based on gnu-make, developed by Eitan Yaffe (eitan.yaffe@gmail.com).

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

To test the example go into the example/basic directory and run:
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
