#
# lists.jl -
#
# Management of Tcl lists of objects.
#

# Let Tcl list be iterable.

function Base.start(iter::TclObj{List})
    objc, objv = __getlistelements(iter.ptr)
    return (0, objc, objv)
end

function Base.done(iter::TclObj{List}, state)
    state[1] ≥ state[2]
end

function Base.next(iter::TclObj{List}, state)
    i, n, objv = state
    i += 1
    item = __objptr_to(Any, __peek(objv, i))
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
            __lappend!(listptr, val)
        end
    catch ex
        __decrrefcount(listptr)
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
    objptr = ccall((:Tcl_NewListObj, libtcl), TclObjPtr,
                   (Cint, Ptr{TclObjPtr}), 0, C_NULL)
    if objptr == C_NULL
        Tcl.error("failed to create an empty Tcl list")
    end
    return objptr
end

function __newlistobj(args...; kwds...) ::TclObjPtr
    listptr = __newlistobj()
    try
        for arg in args
            __lappend!(listptr, arg)
        end
        for (key, val) in kwds
            __lappendoption!(listptr, key, val)
        end
    catch ex
        __decrrefcount(listptr)
        rethrow(ex)
    end
    return listptr
end

__appendlistelement!(listptr::TclObjPtr, itemptr::TclObjPtr) =
    ccall((:Tcl_ListObjAppendElement, libtcl),
          Cint, (TclInterpPtr, TclObjPtr, TclObjPtr), C_NULL, listptr, itemptr)

function __lappend!(listptr::TclObjPtr, item)
    code = __appendlistelement!(listptr, __objptr(item))
    if code != TCL_OK
        Tcl.error("failed to append a new item to the Tcl list")
    end
    nothing
end

__lappendoption!(listptr::TclObjPtr, key::Symbol, val) =
    __lappendoption!(listptr, string(key), val)

function __lappendoption!(listptr::TclObjPtr, key::String, val)
    option = "-"*(length(key) ≥ 1 && key[1] == '_' ? key[2:end] : key)
    code = __appendlistelement!(listptr, __newobj(option))
    if code == TCL_OK
        code = __appendlistelement!(listptr, __objptr(val))
    end
    if code != TCL_OK
        Tcl.error("failed to append a new option to the Tcl list")
    end
    nothing
end

# FIXME: should be Vector, interp for messages
# Tcl_ListObjGetElements will attempt to convert the
# object to a list if it is not one.
function __objptr_to(::Type{List}, listptr::Ptr{Void})
    listptr == C_NULL && return Array{Any}(0)
    objc, objv = __getlistelements(C_NULL, listptr)
    return buildvector(i -> __objptr_to(Any, __peek(objv, i)), objc)
end

function __objptr_to(::Type{List}, interp::TclInterp, listptr::Ptr{Void})
    listptr == C_NULL && return Array{Any}(0)
    objc, objv = __getlistelements(interp.ptr, listptr)
    return buildvector(i -> __objptr_to(Any, interp, __peek(objv, i)), objc)
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

See also: [`Tcl.concat`](@ref), [`Tcl.lindex`](@ref), [`Tcl.lappend!`](@ref).

"""
list(args...; kwds...) = TclObj{List}(__newlistobj(args...; kwds...))

function llength(lst::TclObj{List}) :: Int
    len = Ref{Cint}(0)
    code = ccall((:Tcl_ListObjLength, libtcl), Cint,
                 (TclInterpPtr, TclObjPtr, Ptr{Cint}),
                 C_NULL, lst.ptr, len)
    code == TCL_OK || Tcl.error("failed to query length of list")
    return len[]
end


"""
```julia
Tcl.lappend!(lst, args...; kwds...)
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
function lappend!(list::TclObj{List}, args...; kwds...)
    listptr = list.ptr
    for arg in args
        __lappend!(listptr, arg)
    end
    for (key, val) in kwds
        __lappendoption!(listptr, key, val)
    end
    return list
end

function lappendoption!(list::TclObj{List}, key::Name, val)
    __lappendoption!(list.ptr, __string(key), val)
    return list
end

"""
```julia
Tcl.concat(args...)
```

concatenates the specified arguments and yields a Tcl list.  Compared to
`Tcl.list` which considers that each argument correspond to a single item,
`Tcl.concat` flatten its arguments.

See also: [`Tcl.list`](@ref).

"""
function concat(args...)
    list = TclObj{List}(__newlistobj())
    listptr = list.ptr
    for arg in args
        __concat(listptr, arg)
    end
    return list
end

# Strings are iterables but we want that making a list out of string(s) yields
# a single element per string (not per character) so we have to short-circuit
# __concat(listptr, itr).  Note that `Number` are perfectly usable as iterables
# but we add them to the union below in order to use a faster method for them.

function __concat(listptr::TclObjPtr,
                  arg::Union{AbstractString,Char,Symbol,Number})
    __lappend!(listptr, arg)
end

function __concat(listptr::TclObjPtr, obj::TclObj)
    __lappend!(listptr, arg)
end

function __concat(listptr::TclObjPtr, list::TclObj{List})
    # FIXME: make this faster.
    #for obj in list
    #    __lappend!(listptr, obj)
    #end
    for i in 1:length(list)
        # Use `lindex(TclObj,...` to avoid conversion of items.
        __lappend!(listptr, lindex(TclObj, list, i))
    end
end

# Everything else is assumed to be an iterable.
function __concat(listptr::TclObjPtr, itr) ::TclObjPtr
    for val in itr
        __lappend!(listptr, val)
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
    __itemptr_to(T, __lindex(list, i))

lindex(interp::TclInterp, list::TclObj{List}, i::Integer) =
    lindex(Any, interp, list, i)

lindex(::Type{T}, interp::TclInterp, list::TclObj{List}, i::Integer) where {T} =
    __itemptr_to(T, interp, __lindex(interp, list, i))

__itemptr_to(::Type{T}, interp::TclInterp, objptr::TclObjPtr) where {T} =
    (objptr == C_NULL ? __missing_item(T) : __objptr_to(T, interp, objptr))

__itemptr_to(::Type{T}, objptr::TclObjPtr) where {T} =
    (objptr == C_NULL ? __missing_item(T) : __objptr_to(T, objptr))

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
    code, objptr = __getlistitem(C_NULL, list.ptr, i)
    if code != TCL_OK
        Tcl.error("failed to get Tcl list element at index $i")
    end
    return objptr
end

function __lindex(interp::TclInterp, list::TclObj{List}, i::Integer)
    code, objptr = __getlistitem(interp.ptr, list.ptr, i)
    if code != TCL_OK
        Tcl.error(interp)
    end
    return objptr
end

function __getlistitem(intptr::TclInterpPtr, listptr::TclObjPtr, i::Integer)
    objptr = Ref{TclObjPtr}()
    code = ccall((:Tcl_ListObjIndex, libtcl), Cint,
                 (TclInterpPtr, TclObjPtr, Cint, Ptr{TclObjPtr}),
                 intptr, listptr, i - 1, objptr)
    if code != TCL_OK
        objptr[] = C_NULL
    end
    return code, objptr[]
end

# Yields (objc, objv) do not free this buffer (see Tcl doc.)
function __getlistelements(intptr::TclInterpPtr, listptr::TclObjPtr)
    objc = Ref{Cint}()
    objv = Ref{Ptr{Ptr{Void}}}()
    code = ccall((:Tcl_ListObjGetElements, libtcl), Cint,
                 (TclInterpPtr, Ptr{Void}, Ptr{Cint}, Ptr{Ptr{Ptr{Void}}}),
                 intptr, listptr, objc, objv)
    if code != TCL_OK
        if intptr == C_NULL
            msg = "failed to convert Tcl object into a list"
        else
            msg = __getstringresult(intptr)
        end
        Tcl.error(msg)
    end
    return convert(Int, objc[]), objv[]
end
