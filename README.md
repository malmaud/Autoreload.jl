Autoreload
===============

Autoreload is a package for autoreloading modules in IJulia. It is intended to allow a workflow where you develop Julia source in some editor, while interacting with it via an IJulia notebook or the command-line REPL. It is modeled after IPython's autoreload extension.

Installation
=============
In your ~/.julia directory, type 

```
git clone git@github.com:malmaud/Autoreload.jl.git
```

Usage
=======
First load the package:

```julia
using Autoreload
```

You can then use the ```arequire(filename)``` and ```aimport(modulename)``` commands where you normally would have used ```require``` and ```import```. If you then call ```areload()```, all source included with ```arequire``` and ```aimport``` will be reloaded if the source files have been modified since their last reload. 

A list of files marked for autoreloading can be seen by calling ```arequire()```. A file can be deleted from the autoreload list by calling ```arequire(filename, :off)```.

Module dependencies
====================
There is basic support for handling depencies between files which are to be reloaded. For example, if a file M3.jl should be loaded only after loading files M1.jl and M2.jl (for example, if M3 imports M1 and M2), you can write

```
arequire("M3", depends_on=["M1", "M2"])
```

M3 will then be auto-reloaded if either M1.jl, M2.jl, or M3.jl is edited, will all three files being reloaded in the correct order. ```aimport``` also supports the depends_on keyword. A planned future addition to Autoreload is to automatically determine module dependcies. 


IJulia integration
===================
If you are using IJulia (recommended), then ```areload()``` will automatically be called before each cell is executed. This behavioral can be toggled on and off by calling ```areload(:on)``` and ```areload(:off)```.

Example
========
In a file called M.jl, I have

```julia
x="First version"
```

In an interactive session, I type

```julia
using Autoreload
arequire("M.jl")
x
```
This will evaluate to "First version".

I then edit M.jl to be

```julia
x="Second version"
```

Then in the same interactive session, I type

```julia
areload()
x
```

and get back "Second version". If I had been using IJulia, the call to ```areload()``` would have been unnecessary.

Smart handling of reloaded type definitions
=============================================
If you reload a module that defines  types, any variables accessible in the global scope (the ```Main``` module) that have a type defined in that module will automatically have its type changed to refer to the new module's corresponding type. Here's an example:

A file called M.jl contains:

```julia
module M
type MyType
  x::Int
end

f(var::MyType) = print("First version")
end
```

Then in an interactive session, I have:

```
using Autoreload
aimport("M")
my_var = M.MyType(5)
M.f(my_var)
```

this will print "First version". Now I edit M.jl, and replace it with

```julia
module M
type MyType
  x::Int
end

f(var::MyType) = print("Second version")
end
```

Then in the interactive section, I write

```julia
areload()
M.f(my_var)
```

This will print "Second version". If you had used ```Base.reload("M.jl")``` instead of reloading via Autoreload, "First version" would have been printed in first case, but second case would have resulted in an error.

Limitations
============
Autoreload.jl uses Julia's built-in ```reload``` command, and is subject to all the same limitations. The most noticable is not being be able to redefine types at the global scope. You can get around this by wrapping all type definitions in a module. References to functions and data in code that is reloaded are also potentially problematic. 


Planned future features
==========================

* Don't attempt to load a type declaration  in a required script if it conflicts with a definition in Main, but still load the rest of the script

