#
# lists.jl -
#
# Management of Tcl lists of objects.
#

# Let Tcl list be iterable.

function Base.start(iter::TclObj{List})
    objc, objv = __getlistelements(__objptr(iter))
    return (0, objc, objv)
end

function Base.done(iter::TclObj{List}, state)
    state[1] ≥ state[2]
end

function Base.next(iter::TclObj{List}, state)
    i, n, objv = state
    i += 1
    item = __objptr_to(Any, C_NULL, __peek(objv, i))
    return item, (i, n, objv)
end


# Let Tcl list be indexable.

Base.length(list::TclObj{List}) = llength(list)

Base.endof(list::TclObj{List}) = llength(list)

Base.push!(list::TclObj{List}, args...; kwds...) =
    lappend!(list, args...; kwds...)

Base.getindex(list::TclObj{List}, i::Integer) = lindex(list, i)

function Base.getindex(list::TclObj{List}, msk::AbstractVector{Bool})
    n = countnz(msk)
    v = Array{Any}(n)
    if n < 1
        return v
    end
    len = length(list)
    i = 0
    for j in 1:length(msk)
        if msk[j]
            i += 1
            v[i] = (j ≤ len ? list[j] : nothing)
        end
    end
    return standardizetype(v)
end

Base.getindex(list::TclObj{List}, msk::AbstractArray{Bool}) =
    error("indexing a list by a multi-dimensional array of booleans is not possible")

function Base.getindex(list::TclObj{List}, J::AbstractArray{<:Integer})
    A = similar(J, Any)
    if length(J) < 1
        return A
    end
    len = length(list)
    for i in eachindex(A, J)
        j = J[i]
        A[i] = (1 ≤ j ≤ len ? list[j] : nothing)
    end
    return standardizetype(A)
end

# FIXME: call Tcl_ListObjReplace to implement Base.setindex!
#
# function Base.setindex!(list::TclObj{List}, value, i::Integer)
# end
#
# function Base.setindex!(list::TclObj{List}, value, r::UnitRange)
# end


#
# Implement lists objects (see objects.jl).
#
#     Iterables like vectors and tuples yield lists.  No arguments, yield empty
#     lists.
#

TclObj() = TclObj{List}(__newlistobj())

__newobj() = __newlistobj()

TclObj(itr::Iterables) = TclObj{List}(__newobj(itr))

function __newobj(itr::Iterables) ::TclObjPtr
    listptr = __newlistobj()
    try
        for val in itr
            __lappend(listptr, val)
        end
    catch ex
        Tcl_DecrRefCount(listptr)
        rethrow(ex)
    end
    return listptr
end


"""
```julia
__newlistobj(itr)
```

yields a pointer to a new Tcl list object whose items are taken from
the iterable collection `itr`.

```julia
__newlistobj(args...; kwds...)
```

yields a pointer to a new Tcl list object whose leading items are taken from
`args...` and to which are appended the `(key,val)` pairs from `kwds...` so as
to mimic Tk options.

Beware that the returned object is not managed and has a zero reference count.
The caller is reponsible of taking care of that.

"""
function __newlistobj()
    objptr = Tcl_NewListObj(0, Ptr{TclObjPtr}(0))
    if objptr == C_NULL
        Tcl.error("failed to create an empty Tcl list")
    end
    return objptr
end

function __newlistobj(args...; kwds...) ::TclObjPtr
    listptr = __newlistobj()
    try
        for arg in args
            __lappend(listptr, arg)
        end
        for (key, val) in kwds
            __lappendoption(listptr, key, val)
        end
    catch ex
        Tcl_DecrRefCount(listptr)
        rethrow(ex)
    end
    return listptr
end

function __objptr_to(::Type{Vector}, intptr::TclInterpPtr,
                     listptr::Ptr{Void}) :: Vector
    listptr == C_NULL && return Array{Any}(0)
    objc, objv = __getlistelements(intptr, listptr)
    return buildvector(i -> __objptr_to(Any, intptr, __peek(objv, i)), objc)
end

"""
```julia
buildvector(f, n)
```

yields a vector of length `n` whose elements are `f(i)` for `i ∈ 1:n`.
If possible the type of the elements is standardized.

"""
function buildvector(f::Function, n::Integer)
    v = Array{Any}(n)
    if n ≥ 1
        for i in 1:n
            v[i] = f(i)
        end
        return standardizetype(v)
    end
    return v
end

"""
```julia
standardizetype(A)
```

if all elements of array `A` can be promoted to the same type `T`, returns `A`
converted as a `Array{T}`; otherwise, returns `A` unchanged.  Promotions rules
are a bit different than the ones in Julia, in the sense that the family type
of elements is preserved.  Families are: strings, integers and floats.

"""
function standardizetype(A::AbstractArray{Any,N}) where N
    if length(A) ≥ 1
        T = Ref{DataType}()
        first = true
        for i in eachindex(A)
            T[] = (first ? typeof(A[i]) :
                   __promote_elem_type(T[], typeof(A[i])))
            first = false
        end
        if T[] != Any
            # A common type has been found, promote the vector to this common
            # type.
            return convert(Array{T[],N}, A)
        end
    end
    return A
end

# Rules for combining list element types and find a more precise common type
# than just `Any`.  Combinations of integers are promoted to the largest
# integer type and similarly for floats but mixture of floats and integers
# yield `Any`.

__promote_elem_type(::DataType, ::DataType) = Any

for T in (Integer, AbstractFloat)
    @eval begin

        function __promote_elem_type(::Type{T1},
                                     ::Type{T2}) where {T1<:$T,T2<:$T}
            return promote_type(T1, T2)
        end

        function __promote_elem_type(::Type{Vector{T1}},
                                     ::Type{Vector{T2}}) where {T1<:$T,
                                                                T2<:$T}
            return Vector{promote_type(T1, T2)}
        end

    end
end

__promote_elem_type(::Type{String}, ::Type{String}) = String

__promote_elem_type(::Type{Vector{String}}, ::Type{Vector{String}}) =
    Vector{String}

#------------------------------------------------------------------------------

"""
```julia
list(args...; kwds...)
```

yields a list of Tcl objects consisting of the one object per argument
`args...` (in the same order as they appear) and then followed by two objects
per keyword, say `key=val`, in the form `-key`, `val` (note the hyphen in front
of the keyword name).  To allow for option names that are Julia keywords, a
leading underscore is stripped, if any, in `key`.

Lists are iterable and indexable, as illustrated by the following examples:

``julia
lst = Tcl.list(π,1,"hello",2:6)
lenght(lst) # -> the number of items in the list
lst[1]      # -> 3.1415...
lst[end]    # -> [2,3,4,5,6]
lst[2:3]    # -> Any[1,"hello"]
lst[0]      # -> nothing
lst[end+1]  # -> nothing
for itm in lst
    println(itm)
end
sel = map(i -> isa(i, Number), lst) # -> [true,true,false,false]
lst[sel] # -> Any[3.14159,1]
```

You may note that, (i) like Tcl lists, getting an out of bound list item just
yields nothing; (ii) lists are retrieved as Julia arrays with, if possible,
homogeneous element type (otherwise `Any`).

You may sub-select list elements.  For instance to extract the numbers of a
list:

``julia
lst = Tcl.list(π,1,"hello",2:6)
sel = map(i -> isa(i, Number), lst) # -> [true,true,false,false]
lst[sel] # -> Any[3.14159,1]
```

Use `push!` (or [`Tcl.lappend!`](@ref]) to append elements to a list.  Use
[`Tcl.concat`](@ref) to concatenate lists.

See also: [`Tcl.concat`](@ref), [`Tcl.lindex`](@ref), [`Tcl.lappend!`](@ref),
          [`Tcl.exec`](@ref), .

"""
list(args...; kwds...) = TclObj{List}(__newlistobj(args...; kwds...))

function llength(lst::TclObj{List}) :: Int
    status, length = Tcl_ListObjLength(C_NULL, __objptr(lst))
    status == TCL_OK || Tcl.error("failed to query length of list")
    return length
end

"""
```julia
Tcl.lappend!([interp,] lst, args...; kwds...)
```
or
```julia
push!(lst, args...; kwds...)
```

append to the list `lst` of Tcl objects one object per argument `args...` (in
the same order as they appear) and then followed by two objects per keyword,
say `key=val`, in the form `-key`, `val` (note the hyphen in front of the
keyword name).  To allow for option names that are Julia keywords, a leading
underscore is stripped, if any, in `key`; for instance:

```julia
Tcl.lappend!(lst, _in="something")
```

appends `"-in"` and `something` to the list `lst`.

See also: [`Tcl.list`](@ref).

"""
function lappend!(interp::TclInterp, list::TclObj{List}, args...; kwds...)
    listptr = __objptr(list)
    __set_interpreter(interp)
    try
        @__build_list interp listptr args kwds
    finally
        __reset_interpreter()
    end
    return list
end

lappend!(list::TclObj{List}, args...; kwds...) =
    lappend!(getinterp(), list, args...; kwds...)

# Appending a new item to a list with Tcl_ListObjAppendElement increments the
# reference count of the item, this is the only side effect for the item.  That
# is to say, the appended item is not be duplicated, just shared.  So, to
# manage the memory associated with the item, we can increment its reference
# count before appending and decrement it after without effects on the
# performances.  This is not necessary for a managed object.

function __lappend(intptr::TclInterpPtr, listptr::TclObjPtr, item)
    objptr = Tcl_IncrRefCount(__newobj(item))
    status = Tcl_ListObjAppendElement(intptr, listptr, objptr)
    Tcl_DecrRefCount(objptr)
    if status != TCL_OK
        __lappend_error(intptr)
    end
    nothing
end

function __lappend(intptr::TclInterpPtr, listptr::TclObjPtr,
                   obj::Union{TclObj,TkWidget})
    if Tcl_ListObjAppendElement(intptr, listptr, __objptr(obj)) != TCL_OK
        __lappend_error(intptr)
    end
    nothing
end

function __lappend(intptr::TclInterpPtr, listptr::TclObjPtr, f::Function)
    cmd = __createcommand(intptr, f)
    status = Tcl_ListObjAppendElement(intptr, listptr, __objptr(cmd))
    if status != TCL_OK
        release(cmd)
        __lappend_error(intptr)
    end
    nothing
end

__lappend(listptr::TclObjPtr, item) = __lappend(C_NULL, listptr, item)

__lappend_error(intptr::TclInterpPtr) =
    Tcl.error(__errmsg(intptr, "failed to append a new item to the Tcl list"))

function __lappendoption(intptr::TclInterpPtr, listptr::TclObjPtr,
                         key::String, val)
    # First, append the key.
    option = "-"*(length(key) ≥ 1 && key[1] == '_' ? key[2:end] : key)
    objptr = Tcl_IncrRefCount(__newobj(option))
    status = Tcl_ListObjAppendElement(C_NULL, listptr, objptr)
    Tcl_DecrRefCount(objptr)
    if status == TCL_OK
        # Second, append the value.
        objptr = Tcl_IncrRefCount(__objptr(val))
        status = Tcl_ListObjAppendElement(C_NULL, listptr, objptr)
        Tcl_DecrRefCount(objptr)
    end
    if status != TCL_OK
        Tcl.error("failed to append a new option to the Tcl list")
    end
    nothing
end

__lappendoption(intptr::TclInterpPtr, listptr::TclObjPtr, key::Symbol, val) =
    __lappendoption(intptr, listptr, string(key), val)

__lappendoption(listptr::TclObjPtr, key, val) =
    __lappendoption(C_NULL, listptr, string(key), val)

"""
```julia
Tcl.concat([interp,]args...)
```

concatenates the specified arguments and yields a Tcl list.  Compared to
`Tcl.list` which considers that each argument correspond to a single item,
`Tcl.concat` flatten its arguments and does not accept keyword arguments.

Optional argument `interp` is the Tcl interpreter to use for error reporting
or to create callbacks.

See also: [`Tcl.list`](@ref), [`Tcl.eval`](@ref).

"""
function concat(interp::TclInterp, args...)
    list = TclObj{List}(__newlistobj())
    listptr = __objptr(list)
    @__concat_args interp listptr args
    return list
end

concat(args...) = concat(getinterp(), args...)

# The basic functions used by most Tcl list manipulation functions are
# Tcl_ListObjGetElements, Tcl_ListObjReplace and Tcl_ListObjAppendElement.
# Tcl_ListObjReplace does not call Tcl_ListObjAppendElement.
#
# As a general rule, modifying a shared list is not allowed.  Thus
# Tcl_ListObjReplace and Tcl_ListObjAppendElement must not be applied to a
# shared list object.  This limits the risk of building circular lists.
#

# For atomic objects which are considered as single list element, __concat is
# equivalent to __lappend.
function __concat(intptr::TclInterpPtr, listptr::TclObjPtr,
                  item::Union{AtomicTypes,TclObj{<:AtomicTypes},TkWidget})
    __lappend(intptr, listptr, item)
end

# Strings are iterables but we want that making a list out of string(s) yields
# a single element per string (not per character) so we have to short-circuit
# __concat(listptr, itr).  Note that `Number` are perfectly usable as iterables
# but we add them to the union below in order to use a faster method for them.
function __concat(intptr::TclInterpPtr, listptr::TclObjPtr,
                  str::AbstractString)
    objptr = Tcl_IncrRefCount(__newobj(str))
    status = Tcl_ListObjAppendList(intptr, listptr, objptr)
    Tcl_DecrRefCount(objptr)
    if status != TCL_OK
        msg = __errmsg(intptr, "failed to concatenate a string to a Tcl list")
        Tcl.error(msg)
    end
end

function __concat(intptr::TclInterpPtr, listptr::TclObjPtr, obj::TclObj)
    status = Tcl_ListObjAppendList(intptr, listptr, __objptr(obj))
    if status != TCL_OK
        msg = __errmsg(intptr, "failed to concatenate Tcl lists")
        Tcl.error(msg)
    end
end

# Everything else is assumed to be an iterable.
function __concat(intptr::TclInterpPtr, listptr::TclObjPtr, itr) ::TclObjPtr
    for val in itr
        __concat(intptr, listptr, val)
    end
end

"""
```julia
Tcl.lindex([T,] [interp,] list, i)
```

yields the element at index `i` in Tcl list `list`.  An *empty* result is
returned if index is out of range.

If optional argument `T` is omitted, the type of the returned value reflects
that of the Tcl variable; otherwise, `T` can be `String` to get the string
representation of the value or `TclObj` to get a managed Tcl object.  The
latter type is more efficient if the returned item is intended to be put in a
Tcl list or to be an argument of a Tcl script or command.

Tcl interpreter `interp` may be provided to have more detailed error messages
in case of failure.

See also: [`Tcl.list`](@ref), [`Tcl.getvar`](@ref).

"""
lindex(list::TclObj{List}, i::Integer) =
    lindex(Any, list, i)

lindex(::Type{T}, list::TclObj{List}, i::Integer) where {T} =
    __itemptr_to(T, C_NULL, __lindex(list, i))

lindex(interp::TclInterp, list::TclObj{List}, i::Integer) =
    lindex(Any, interp, list, i)

lindex(::Type{T}, interp::TclInterp, list::TclObj{List}, i::Integer) where {T} =
    __itemptr_to(T, interp.ptr, __lindex(interp, list, i))

__itemptr_to(::Type{T}, intptr::TclInterpPtr, objptr::TclObjPtr) where {T} =
    (objptr == C_NULL ? __missing_item(T) : __objptr_to(T, intptr, objptr))

"""
```julia
___missing_item(T)
```

yields the value of missing list item of type `T`.  May throw an error if
missing items of such type are not allowed.

"""
__missing_item(::Type{String}) = ""
__missing_item(::Type{Any}) = nothing
__itemptr_item(::Type{TclObj}) = TclObj()
__itemptr_item(::Type{Vector}) = Array{Any}(0)
__missing_item(::Type{T}) where {T<:Union{Integer,AbstractFloat}} = zero(T)
__missing_item(::Type{Char}) = '\0'

# Get a list item.
#
#     The convention of Tcl_ListObjIndex is to return TCL_ERROR if some error
#     occured and TCL_OK with a NULL pointer if index is out of range.

function __lindex(list::TclObj{List}, i::Integer)
    status, objptr = Tcl_ListObjIndex(C_NULL, __objptr(list), i)
    if status != TCL_OK
        Tcl.error("failed to get Tcl list element at index $i")
    end
    return objptr
end

function __lindex(interp::TclInterp, list::TclObj{List}, i::Integer)
    status, objptr = Tcl_ListObjIndex(interp.ptr, __objptr(list), i)
    if status != TCL_OK
        Tcl.error(interp)
    end
    return objptr
end

# Yields (objc, objv) do not free this buffer (see Tcl doc.)
function __getlistelements(intptr::TclInterpPtr, listptr::TclObjPtr)
    status, objc, objv = Tcl_ListObjGetElements(intptr, listptr)
    if status != TCL_OK
        msg = __errmsg(intptr, "failed to convert Tcl object into a list")
        Tcl.error(msg)
    end
    return objc, objv
end
