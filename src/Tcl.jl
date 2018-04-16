__precompile__(true)

module Tcl

if isfile(joinpath(dirname(@__FILE__),"..","deps","deps.jl"))
    include("../deps/deps.jl")
else
    error("Tcl not properly installed.  Please run `Pkg.build(\"Tcl\")` to create file \"",joinpath(dirname(@__FILE__),"..","deps","deps.jl"),"\"")
end

export
    TclError,
    TclInterp,
    TclObj,
    TclObjList,
    TclObjCommand,
    TclStatus,
    TCL_OK,
    TCL_ERROR,
    TCL_RETURN,
    TCL_BREAK,
    TCL_CONTINUE,
    TCL_GLOBAL_ONLY,
    TCL_NAMESPACE_ONLY,
    TCL_APPEND_VALUE,
    TCL_LIST_ELEMENT,
    TCL_LEAVE_ERR_MSG,
    TCL_DONT_WAIT,
    TCL_WINDOW_EVENTS,
    TCL_FILE_EVENTS,
    TCL_TIMER_EVENTS,
    TCL_IDLE_EVENTS,
    TCL_ALL_EVENTS,
    TCL_NO_EVAL,
    TCL_EVAL_GLOBAL,
    TCL_EVAL_DIRECT,
    TCL_EVAL_INVOKE,
    TCL_CANCEL_UNWIND,
    TCL_EVAL_NOERR,
    tclerror,
    tcleval,
    tkstart,
    @TkWidget,
    TkObject,
    TkImage,
    TkWidget,
    TkRootWidget,
    TkButton,
    TkCanvas,
    TkCheckbutton,
    TkEntry,
    TkFrame,
    TkLabel,
    TkLabelframe,
    TkListbox,
    TkMenu,
    TkMenubutton,
    TkMessage,
    TkPanedwindow,
    TkRadiobutton,
    TkRoot,
    TkScale,
    TkScrollbar,
    TkSpinbox,
    TkText,
    TkToplevel,
    TkWidget,
    TtkButton,
    TtkCheckbutton,
    TtkCombobox,
    TtkEntry,
    TtkFrame,
    TtkLabel,
    TtkLabelframe,
    TtkMenubutton,
    TtkNotebook,
    TtkPanedwindow,
    TtkProgressbar,
    TtkRadiobutton,
    TtkScale,
    TtkScrollbar,
    TtkSeparator,
    TtkSizegrip,
    TtkSpinbox,
    TtkTreeview

if VERSION < v"0.6.0"
    # macro for raw strings (will be part of Julia 0.6, see PR #19900 at
    # https://github.com/JuliaLang/julia/pull/19900).
    export @raw_str
    macro raw_str(s); s; end
end

include("types.jl")
include("basics.jl")
include("objects.jl")
include("lists.jl")
include("variables.jl")
include("widgets.jl")
include("dialogs.jl")
include("images.jl")
include("shortnames.jl")

end # module
