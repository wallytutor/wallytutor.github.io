module AuChimiste

__init__() = nothing

using Base
using DataFrames
using Symbolics

using DocStringExtensions: TYPEDFIELDS
using StaticArrays: SVector, SMatrix

import YAML

export AuChimisteDatabase

#region: interfaces
abstract type ChemicalException       <: Exception end
abstract type ChemicalElementsError   <: ChemicalException end
abstract type ChemicalComponentsError <: ChemicalException end

abstract type AbstractThermodynamicData end
abstract type AbstractThermodynamicsModel end
abstract type AbstractTransportModel end

"""
    molar_mass(args...; kwargs...)

Evaluation of the molar mass of a substance.
Its return value must be in ``kg\\cdotp{}mol^{-3}``.
"""
function molar_mass end

"""
    density(args...; kwargs...)

Evaluation of the density of a substance.
Its return value must be in ``kg\\cdotp{}m^{-3}``.
"""
function density end

"""
    specific_heat(args...; kwargs...)

Evaluation of the specific heat of a substance.
Its return value must be in ``J\\cdotp{}kg^{-1}\\cdotp{}K^{-1}``.
"""
function specific_heat end

"""
    enthalpy(args...; kwargs...)

Evaluation of the enthalpy of a substance.
Its return value must be in ``J\\cdotp{}kg^{-1}``.
"""
function enthalpy end

"""
    entropy(args...; kwargs...)

Evaluation of the entropy of a substance.
Its return value must be in ``J\\cdotp{}K^{-1}``.
"""
function entropy end

"""
    thermal_conductivity(args...; kwargs...)

Evaluation of the thermal conductivity of a substance.
Its return value must be in ``W\\cdotp{}m^{-1}\\cdotp{}K^{-1}``.
"""
function thermal_conductivity end

"""
    viscosity(args...; kwargs...)

Evaluation of the viscosity of a substance.
Its return value must be in ``Pa\\cdotp{}s``.
"""
function viscosity end

function Base.show(io::IO, err::ChemicalException)
    print(io, "$(nameof(typeof(err))): $(err.message)")
end

function Base.showerror(io::IO, err::ChemicalException)
    Base.show(io, err)
end
#endregion: interfaces

#region: constants
"Electron Mass ``m_e`` [$(ELECTRON_MASS) kg]"
const ELECTRON_MASS = 9.109_382_915e-31

"Avogadro's Number ``N_\\mathrm{A}`` [$(AVOGADRO) number/kmol]"
const AVOGADRO = 6.022_140_76e26

"Ideal gas constant ``R`` [$(GAS_CONSTANT) J/(mol.K)]."
const GAS_CONSTANT::Float64 = 8.314_462_618_153_24

"Stefan-Boltzmann constant ``\\sigma`` [$(STEFAN_BOLTZMANN) W/(m².K⁴)]."
const STEFAN_BOLTZMANN::Float64 = 5.670_374_419e-08

"Reference atmospheric pressure [$(P_NORMAL) Pa]."
const P_NORMAL::Float64 = 101325.0

"Normal atmospheric temperature [$(T_NORMAL) K]."
const T_NORMAL::Float64 = 273.15

"Normal atmospheric concentration [$(C_NORMAL) mol/m³]. "
const C_NORMAL::Float64 = P_NORMAL / (GAS_CONSTANT * T_NORMAL)

"Standard atmospheric temperature [$(T_STANDARD) K]."
const T_STANDARD::Float64 = 298.15

"Conversion factor from calories to joules [$(JOULE_PER_CALORIE) J/cal]."
const JOULE_PER_CALORIE::Float64 = 4.184
#endregion: constants

#region: elements
"Element (or isotope) was not found in user database."
struct NoSuchElementError <: ChemicalElementsError
    message::String

    function NoSuchElementError(e)
        return new("""\
            No such element $(e) in the elements dictionary. If you are \
            trying to access an isotope, please make sure you create it \
            before.
            """)
    end
end

"Unstable elements do not provide atomic mass."
struct NoIsotopeProvidedError <: ChemicalElementsError
    message::String

    function NoIsotopeProvidedError(e)
        return new("""\
            Accessing the atomic mass of unstable element $(e) is not \
            supported. Please consider creating a named isotope of \
            this element with `add_isotope`.
            """)
    end
end

"A composition set is missing for the given component."
struct EmptyCompositionError <: ChemicalComponentsError
    message::String

    function EmptyCompositionError()
        return new("""\
            Cannot create a composition with an empty set. Please \
            supply the elements and related amounts accoding to the \
            type of composition specification.
            """)
    end
end

"The provided scaler targets an unspecified element."
struct InvalidScalerError <: ChemicalComponentsError
    message::String

    function InvalidScalerError(s, e)
        return new("""\
            Scaling configuration must be a valid element from the \
            system. Could not find $(s) among $(e).
            """)
    end
end

"""
Represents a chemical element.

Fields
======
$(TYPEDFIELDS)
"""
struct AtomicData
    "Element symbol in periodic table."
    symbol::String

    "Element name in periodic table."
    name::String

    "Element number in atomic units."
    number::Int64

    "Element atomic mass [kg/kmol]."
    mass::Float64
end

function Base.show(io::IO, e::AtomicData)
    print(io, "$(e.symbol) ($(e.number), $(e.name)) $(e.mass) kg/kmol")
end

"""
    has_element(e::Union{String, Symbol})

Check if element exists in list of atomic symbols.
"""
function has_element(e::Union{String, Symbol})
    return haskey(USER_ELEMENTS, Symbol(e))
end

"""
    list_elements()

Provides access to the list of atomic symbols.
"""
function list_elements()
    return Vector{Symbol}([keys(USER_ELEMENTS)...])
end

"""
    reset_elements_table()

Remove any user-defined element.
"""
function reset_elements_table()
    empty!(USER_ELEMENTS)
    merge!(USER_ELEMENTS, ELEMENTS)
    return
end

"""
    add_element(
        symbol::String,
        name::String,
        number::Int64,
        mass::Float64;
        verbose = true
    )

Create chemical element `name` with associated `symbol` and atomic
`number`. The value of atomic `mass` is given in grams per mole.
"""
function add_element(
        symbol::Union{Symbol,String},
        name::String,
        number::Int64,
        mass::Float64;
        verbose = true
    )
    key = Symbol(symbol)

    if haskey(USER_ELEMENTS, key)
        verbose && @warn("""
        The provided element $(key) is already present in the \
        elements dictionary. If you are trying to create an \
        isotope, please chose a different name. Also notice that \
        default stable elements cannot be modified.
        """)
        return
    end

    use_symbol = String(symbol)

    USER_ELEMENTS[key] = AtomicData(use_symbol, name, number, mass)

    return USER_ELEMENTS[key]
end

"""
    add_isotope(
        symbol::String,
        mass::Float64;
        name = nothing,
        verbose = true
    )

Create isotope of element `symbol` with provided `mass` in grams per
mole. If isothope is known by a specific `name` then use it instead
of a *name-mass* naming scheme.
"""
function add_isotope(
        symbol::Union{Symbol,String},
        mass::Float64;
        name = nothing,
        verbose = true
    )
    key = Symbol(symbol)

    !haskey(USER_ELEMENTS, key) && throw(NoSuchElementError(key))

    e = USER_ELEMENTS[key]

    iso_mass = convert(Int64, round(mass, RoundNearest))

    iso_symbol = "$(e.symbol)$(iso_mass)"

    iso_name = isnothing(name) ? "$(e.name)-$(iso_mass)" : name

    return add_element(iso_symbol, iso_name, e.number, mass; verbose)
end

@doc """
    atomic_mass(e::AtomicData)
    atomic_mass(e::Union{String,Symbol})

Atomic mass of element [g/mol].
""" atomic_mass

function atomic_mass(e::AtomicData)
    (e.mass < 0.0) && throw(NoIsotopeProvidedError(e.symbol))
    return e.mass
end

function atomic_mass(e::Union{String,Symbol})
    return handle_element(atomic_mass, e)
end

@doc """
    atomic_number(e::AtomicData)
    atomic_number(e::Union{String,Symbol})

Atomic number of element.
""" atomic_number

function atomic_number(e::AtomicData)
    return e.number
end

function atomic_number(e::Union{String,Symbol})
    return handle_element(atomic_number, e)
end

@doc """
    element_name(e::AtomicData)
    element_name(e::Union{String,Symbol})

Element name from atomic symbol.
""" element_name

function element_name(e::AtomicData)
    return e.name
end

function element_name(e::Union{String,Symbol})
    return handle_element(element_name, e)
end

@doc """
    element(e::Int64)
    element(e::Union{String,Symbol})

Element data from symbol or number.
""" element

function element(e::Int64)
    return find_element(e, :number)
end

function element(e::Union{String,Symbol})
    return find_element(String(e), :symbol)
end

"""
Default table of elements. This table should not be modified by any
internal or external operation. Although it is declared as constant,
that means simply that `ELEMENTS` cannot be attributed to, but the
resulting dictionary may be accidentally modified.
"""
const ELEMENTS = let
    mapping(e) = Symbol(e[1]) => AtomicData(e...)

    data = map(mapping, [
        ("H",  "hydrogen",      1,     1.008),
        ("He", "helium",        2,     4.002602),
        ("Li", "lithium",       3,     6.94),
        ("Be", "beryllium",     4,     9.0121831),
        ("B",  "boron",         5,    10.81),
        ("C",  "carbon",        6,    12.011),
        ("N",  "nitrogen",      7,    14.007),
        ("O",  "oxygen",        8,    15.999),
        ("F",  "fluorine",      9,    18.998403163),
        ("Ne", "neon",         10,    20.1797),
        ("Na", "sodium",       11,    22.98976928),
        ("Mg", "magnesium",    12,    24.305),
        ("Al", "aluminum",     13,    26.9815384),
        ("Si", "silicon",      14,    28.085),
        ("P",  "phosphorus",   15,    30.973761998),
        ("S",  "sulfur",       16,    32.06),
        ("Cl", "chlorine",     17,    35.45),
        ("Ar", "argon",        18,    39.95),
        ("K",  "potassium",    19,    39.0983),
        ("Ca", "calcium",      20,    40.078),
        ("Sc", "scandium",     21,    44.955908),
        ("Ti", "titanium",     22,    47.867),
        ("V",  "vanadium",     23,    50.9415),
        ("Cr", "chromium",     24,    51.9961),
        ("Mn", "manganese",    25,    54.938043),
        ("Fe", "iron",         26,    55.845),
        ("Co", "cobalt",       27,    58.933194),
        ("Ni", "nickel",       28,    58.6934),
        ("Cu", "copper",       29,    63.546),
        ("Zn", "zinc",         30,    65.38),
        ("Ga", "gallium",      31,    69.723),
        ("Ge", "germanium",    32,    72.630),
        ("As", "arsenic",      33,    74.921595),
        ("Se", "selenium",     34,    78.971),
        ("Br", "bromine",      35,    79.904),
        ("Kr", "krypton",      36,    83.798),
        ("Rb", "rubidium",     37,    85.4678),
        ("Sr", "strontium",    38,    87.62),
        ("Y",  "yttrium",      39,    88.90584),
        ("Zr", "zirconium",    40,    91.224),
        ("Nb", "nobelium",     41,    92.90637),
        ("Mo", "molybdenum",   42,    95.95),
        ("Tc", "technetium",   43,    -1.0),
        ("Ru", "ruthenium",    44,   101.07),
        ("Rh", "rhodium",      45,   102.90549),
        ("Pd", "palladium",    46,   106.42),
        ("Ag", "silver",       47,   107.8682),
        ("Cd", "cadmium",      48,   112.414),
        ("In", "indium",       49,   114.818),
        ("Sn", "tin",          50,   118.710),
        ("Sb", "antimony",     51,   121.760),
        ("Te", "tellurium",    52,   127.60 ),
        ("I",  "iodine",       53,   126.90447),
        ("Xe", "xenon",        54,   131.293),
        ("Cs", "cesium",       55,   132.90545196),
        ("Ba", "barium",       56,   137.327),
        ("La", "lanthanum",    57,   138.90547),
        ("Ce", "cerium",       58,   140.116),
        ("Pr", "praseodymium", 59,   140.90766),
        ("Nd", "neodymium",    60,   144.242),
        ("Pm", "promethium",   61,    -1.0),
        ("Sm", "samarium",     62,   150.36),
        ("Eu", "europium",     63,   151.964),
        ("Gd", "gadolinium",   64,   157.25),
        ("Tb", "terbium",      65,   158.925354),
        ("Dy", "dysprosium",   66,   162.500),
        ("Ho", "holmium",      67,   164.930328),
        ("Er", "erbium",       68,   167.259),
        ("Tm", "thulium",      69,   168.934218),
        ("Yb", "ytterbium",    70,   173.045),
        ("Lu", "lutetium",     71,   174.9668),
        ("Hf", "hafnium",      72,   178.49),
        ("Ta", "tantalum",     73,   180.94788),
        ("W",  "tungsten",     74,   183.84),
        ("Re", "rhenium",      75,   186.207),
        ("Os", "osmium",       76,   190.23 ),
        ("Ir", "iridium",      77,   192.217),
        ("Pt", "platinum",     78,   195.084),
        ("Au", "gold",         79,   196.966570),
        ("Hg", "mercury",      80,   200.592),
        ("Tl", "thallium",     81,   204.38),
        ("Pb", "lead",         82,   207.2 ),
        ("Bi", "bismuth",      83,   208.98040),
        ("Po", "polonium",     84,    -1.0),
        ("At", "astatine",     85,    -1.0),
        ("Rn", "radon",        86,    -1.0),
        ("Fr", "francium",     87,    -1.0),
        ("Ra", "radium",       88,    -1.0),
        ("Ac", "actinium",     89,    -1.0),
        ("Th", "thorium",      90,   232.0377),
        ("Pa", "protactinium", 91,   231.03588),
        ("U",  "uranium",      92,   238.02891),
        ("Np", "neptunium",    93,    -1.0),
        ("Pu", "plutonium",    94,    -1.0),
        ("Am", "americium",    95,    -1.0),
        ("Cm", "curium",       96,    -1.0),
        ("Bk", "berkelium",    97,    -1.0),
        ("Cf", "californium",  98,    -1.0),
        ("Es", "einsteinium",  99,    -1.0),
        ("Fm", "fermium",      100,   -1.0),
        ("Md", "mendelevium",  101,   -1.0),
        ("No", "nobelium",     102,   -1.0),
        ("Lr", "lawrencium",   103,   -1.0),
        ("Rf", "rutherfordium",104,   -1.0),
        ("Db", "dubnium",      105,   -1.0),
        ("Sg", "seaborgium",   106,   -1.0),
        ("Bh", "bohrium",      107,   -1.0),
        ("Hs", "hassium",      108,   -1.0),
        ("Mt", "meitnerium",   109,   -1.0),
        ("Ds", "darmstadtium", 110,   -1.0),
        ("Rg", "roentgenium",  111,   -1.0),
        ("Cn", "copernicium",  112,   -1.0),
        ("Nh", "nihonium",     113,   -1.0),
        ("Gl", "flerovium",    114,   -1.0),
        ("Mc", "moscovium",    115,   -1.0),
        ("Lv", "livermorium",  116,   -1.0),
        ("Ts", "tennessine",   117,   -1.0),
        ("Og", "oganesson",    118,   -1.0),
    ])

    Dict(data)
end

"""
Runtime modifiable table of elements. All operations must be performed
in this table so that user-defined elements (isothopes) can be made
available. This is the table to be internally modified and read by all
functions requiring to access data.
"""
const USER_ELEMENTS = deepcopy(ELEMENTS)

"""
    handle_element(f, e)

Applies function `f` to element `e`. This function wraps the call of
`f` with a standardized error-handling used accross the module.
"""
function handle_element(f, e)
    e = (e isa String) ? Symbol(e) : e
    !has_element(e) && throw(NoSuchElementError(e))
    return f(USER_ELEMENTS[e])
end

"""
    find_element(v, prop)

Find element for which property `prop` has value `v`.
"""
function find_element(v, prop)
    selector(kv) = getproperty(kv[2], prop) == v
    return filter(selector, USER_ELEMENTS) |> values |> first
end
#endregion: elements

#region: components
"""
Represents a chemical component.

Fields
======
$(TYPEDFIELDS)

Notes
=====

- This structure is not intended to be called as a constructor,
  safe use of its features require using [`component`](@ref)
  construction in combination with a composition specification.

- The array of elements is unsorted when construction is performed
  through [`component`](@ref) but may get rearranged when composing
  new chemical components through supported algebra.

- Care must be taken when using `molar_mass` because it is given
  for the associated coefficients. That is always the expected
  behavior for molecular components but might not be the case in
  other applications (solids, solutions) when the mean molecular
  mass may be required.
"""
struct ChemicalComponent
    "Array of component symbols."
    elements::Vector{Symbol}

    "Array of stoichiometric coefficients."
    coefficients::Vector{Float64}

    "Array of elemental mole fractions."
    mole_fractions::Vector{Float64}

    "Array of elemental mass fractions."
    mass_fractions::Vector{Float64}

    "Molar mass of corresponding stoichiometry."
    molar_mass::Float64

    "Global charge of component."
    charge::Number
end

"""
Represents a quantity of component.

Fields
======
$(TYPEDFIELDS)
"""
struct ComponentQuantity
    "Mass of component in arbitrary units."
    mass::Float64

    "Elemental composition of component."
    composition::ChemicalComponent
end

"""
Provides specification of allowed chemical composition types, which
are used to declare compositions in terms of one of the following
specification methods:

- `Stoichiometry`: stoichiometric coefficients
- `MoleProportion`: molar proportions of elements
- `MassProportion`: mass proportions of elements
"""
@enum CompositionTypes begin
    Stoichiometry
    MoleProportion
    MassProportion
end

"""
Creates a typed composition specification for later construction of
chemical component with [`component`](@ref). Generally the end-user
is not expected to use this structure directly, wrappers being
provided by the available composition types through functions
[`stoichiometry`](@ref), [`mole_proportions`](@ref), and
[`mass_proportions`](@ref).

Fields
======
$(TYPEDFIELDS)
"""
struct Composition{T}
    "Tuple of elements and their amounts."
    data::NamedTuple

    "Scaler element and coefficient for construction of component."
    scale::Pair{Symbol,<:Number}

    function Composition{T}(;
            scale::Union{Nothing, Pair{Symbol, <:Number}} = nothing,
            kw...
        ) where T
        # Empty composition keywords is unacceptable:
        isempty(kw) && throw(EmptyCompositionError())

        # Handle absence of scaling for generality:
        scale = something(scale, first(kw))

        # Enforce type of data (no duplicates!)
        data = NamedTuple(kw)

        # Validate existence of scaling element:
        let
            scaler = scale.first
            elements = keys(data)

            scaler in elements || begin
                throw(InvalidScalerError(scaler, elements))
            end
        end

        # Create and return object:
        return new{T}(data, scale)
    end
end

@doc """
    component(spec; kw...)
    component(c::Composition{Stoichiometry}, charge)
    component(c::Composition{MoleProportion}, charge)
    component(c::Composition{MassProportion}, charge)
    component(c::Dict, charge)

Compile component from given composition specification. This function
is a wrapper eliminating the need of calling [`stoichiometry`](@ref),
[`mole_proportions`](@ref) or [`mass_proportions`](@ref) directly. The
value of `spec` must be the symbol representing one of their names.

**Note:** the overload supporting a dictionary input is intended only
for parsing database species data; its direct use is discouraged.
""" component

macro component(func, comp, charge)
    quote
        comp  = $(esc(comp))

        # Values that can be retrieved directly from `c`:
        elems = vcat(keys(comp.data)...)
        coefs = vcat(values(comp.data)...)
        W     = atomic_mass.(elems)
        idx   = findfirst(x->x==comp.scale.first, elems)

        # No matter what is the input type, normalize coefficients:
        U     = coefs ./ sum(coefs)

        # Function `f` converts unit and sort arguments
        X, Y = $(func)(U, W)

        coefs = (comp.scale.second / X[idx]) .* X
        M     = coefs' * W

        ChemicalComponent(elems, coefs, X, Y, M, $(esc(charge)))
    end
end

function component(spec::Symbol; charge = 0, kw...)
    valid = [:stoichiometry, :mole_proportions, :mass_proportions]
    spec in valid || error("Invalid composition specification $(spec)")
    c = getfield(AuChimiste, spec)(; kw...)
    return component(c, charge)
end

function component(c::Composition{Stoichiometry}, charge)
    @component((X, W)->(X, get_mass_fractions(X, W)), c, charge)
end

function component(c::Composition{MoleProportion}, charge)
    @component((X, W)->(X, get_mass_fractions(X, W)), c, charge)
end

function component(c::Composition{MassProportion}, charge)
    @component((Y, W)->(get_mole_fractions(Y, W), Y), c, charge)
end

function component(c::Dict)
    # Retrieve charge of component:
    charge = -1get(c, "E", 0)

    # Delete electron from composition:
    haskey(c, "E") && delete!(c, "E")

    # Handle electron as species without composition:
    isempty(c) && return

    c = NamedTuple(zip(Symbol.(keys(c)), values(c)))
    component(:stoichiometry; charge = charge, c...)
end

"""
    stoichiometry(; kw...)

Create composition based on elemental stoichiometry.
"""
function stoichiometry(; kw...)
    Composition{Stoichiometry}(; kw...)
end

"""
    mole_proportions(; scale = nothing, kw...)

Create composition based on relative molar proportions. The main
different w.r.t. [`stoichiometry`](@ref) is the presence of a
scaling factor to correct stoichiometry representation of the
given composition.
"""
function mole_proportions(; scale = nothing, kw...)
    scale = something(scale, first(kw).first => 1.0)
    Composition{MoleProportion}(; scale, kw...)
end

"""
    mass_proportions(; scale = nothing, kw...)

Create composition based on relative molar proportions. This is
essentially the same thing as [`mole_proportions`](@ref) but in
this case the element keywords are interpreted as being the mass
proportions ofa associated elements.
"""
function mass_proportions(; scale = nothing, kw...)
    scale = something(scale, first(kw).first => 1.0)
    return Composition{MassProportion}(; scale, kw...)
end

"""
    stoichiometry_map(c::ChemicalComponent)

Returns component map of elemental stoichiometry.
"""
function stoichiometry_map(c::ChemicalComponent)
   return NamedTuple(zip(c.elements, c.coefficients))
end

"""
    mole_fractions_map(c::ChemicalComponent)

Returns component map of elemental mole fractions.
"""
function mole_fractions_map(c::ChemicalComponent)
   return NamedTuple(zip(c.elements, c.mole_fractions))
end

"""
    mass_fractions_map(c::ChemicalComponent)

Returns component map of elemental mass fractions.
"""
function mass_fractions_map(c::ChemicalComponent)
   return NamedTuple(zip(c.elements, c.mass_fractions))
end

@doc """
    quantity(c::ChemicalComponent, mass::Float64)
    quantity(spec::Symbol, mass::Float64; kw...)

Creates a quantity of chemical component. It may be explicit, *i.e.*
by providing directly a [`ChemicalComponent`](@ref), or implicit, that
means, by creating a component directly from its chemical composition
and specification method (wrapping [`component`](@ref)).
""" quantity

function quantity(c::ChemicalComponent, mass::Float64)
    return ComponentQuantity(mass, c)
end

function quantity(spec::Symbol, mass::Float64; kw...)
    return quantity(component(spec; kw...), mass)
end

function Base.:*(scale::Number, comp::ChemicalComponent)::ChemicalComponent
    newcomp = zip(comp.elements, scale * comp.coefficients)
    newchrg = scale * comp.charge
    return component(:stoichiometry; charge = newchrg, newcomp...)
end

function Base.:*(comp::ChemicalComponent, scale::Number)::ChemicalComponent
    return scale * comp
end

function Base.:+(ca::ChemicalComponent, cb::ChemicalComponent)::ChemicalComponent
    elements = sort(union(ca.elements, cb.elements))

    # TODO: this is probably faster and more readable than using an
    # index look-up approach, but I need to test that too because
    # it avoids creating intermediate elements (memory footprint).
    da = Dict(zip(ca.elements, ca.coefficients))
    db = Dict(zip(cb.elements, cb.coefficients))

    f(e) = get(da, e, 0.0) + get(db, e, 0.0)
    newcomp = map(e->Pair(e, f(e)), elements)

    charge = ca.charge + cb.charge

    return component(:stoichiometry; charge, newcomp...)
end

function Base.:-(ca::ChemicalComponent, cb::ChemicalComponent)::ChemicalComponent
    tmp = ca + (-1cb)

    if any(tmp.coefficients .< 0)
        @warn("""\
              Component subtraction is fragile and must be used with care. \
              The component operation you tried to perform produced negative \
              coefficients. That is because the right component have more of \
              one/some elements than the left component. Instead of retuning \
              the meaningless composition I am providing you with the mass \
              imbalance.
              """)

        cmp = Tuple(zip(tmp.elements, tmp.coefficients))
        newcomp = map(p->p[1]=>-1p[2], filter(p->last(p) < 0, cmp))
        return component(:stoichiometry; newcomp...)
    end

    return tmp
end

function Base.:*(scale::Number, qty::ComponentQuantity)
    return ComponentQuantity(scale * qty.mass, qty.composition)
end

function Base.:*(qty::ComponentQuantity, scale::Number)
    return scale * qty
end

function Base.:+(qa::ComponentQuantity, qb::ComponentQuantity)
    ma, mb = qa.mass, qb.mass
    mass = ma + mb

    ca, cb = qa.composition, qb.composition
    elements = sort(union(ca.elements, cb.elements))

    # TODO: this is probably faster and more readable than using an
    # index look-up approach, but I need to test that too because
    # it avoids creating intermediate elements (memory footprint).
    da = Dict(zip(ca.elements, ca.mass_fractions))
    db = Dict(zip(cb.elements, cb.mass_fractions))

    f(e) = ma * get(da, e, 0.0) + mb * get(db, e, 0.0)
    newcomp = map(e->Pair(e, f(e)), elements)

    c = component(:mass_proportions; newcomp...)
    return ComponentQuantity(mass, c)
end
#endregion: components

#region: physical-chemistry
"""
    mean_molecular_mass(U, W; basis)

Compute mean molecular mass based on given composition data.
"""
function mean_molecular_mass(U, W; basis)
    basis == :mole && return mean_molecular_mass_x(U, W)
    basis == :mass && return mean_molecular_mass_y(U, W)
    error("Unknown composition basis $(basis).")
end

@doc """
    get_mole_fractions(Y, W)
    get_mole_fractions(Y, W, M)

Get mole fractions from mass fractions.
""" get_mole_fractions

function get_mole_fractions(Y, W)
    mean_molecular_mass_y(Y, W) * @. Y / W
end

function get_mole_fractions(Y, W, M)
    M * @. Y / W
end

@doc """
    get_mass_fractions(X, W)
    get_mass_fractions(X, W, M)

Get mass fractions from mole fractions.
""" get_mass_fractions

function get_mass_fractions(X, W)
    (@. X * W) / mean_molecular_mass_x(X, W)
end

function get_mass_fractions(X, W, M)
    (@. X * W) / M
end

"""
    mean_molecular_mass_y(Y, W)

Mean molecular mass computed from mass fractions.
"""
function mean_molecular_mass_y(Y, W)
    sum(@. Y / W)^(-1.0)
end

"""
    mean_molecular_mass_x(X, W)

Mean molecular mass computed from mole fractions.
"""
function mean_molecular_mass_x(X, W)
    sum(@. X * W)
end
#endregion: physical-chemistry

#region: path
"Default search path for thermodynamics and kinetics databases."
const DATA_PATH = joinpath(dirname(@__DIR__), "data")

"List of search paths for thermodynamics and kinetics databases."
const USER_PATH = [DATA_PATH, pwd(), expanduser("~")]

function loadpath()
    sort(deepcopy(USER_PATH))
end

function addloadpath(path)
    path = abspath(path)
    !isdir(path) && error("Missing directory $(path)")
    !(path in USER_PATH) && push!(USER_PATH, path)
    nothing
end

function resetloadpath()
    empty!(USER_PATH)
    push!(USER_PATH, DATA_PATH, pwd(), expanduser("~"))
end
#endregion: path

#region: thermo-parameterizations
# XXX: MaierKelleyCoefs could be variable size, handle this in the
# future by generalizing with LaurentPolynomial objects!
const Nasa7Coefs       = SVector{7, Float64}
const Nasa9Coefs       = SVector{9, Float64}
const ShomateCoefs     = SVector{8, Float64}
const MaierKelleyCoefs = SVector{5, Float64}

function specific_heat_nasa(T, c::Nasa7Coefs)
    f = c[4] + T * c[5]
    f = c[3] + T * f
    f = c[2] + T * f
    f = c[1] + T * f
    f
end

function specific_heat_nasa(T, c::Nasa9Coefs)
    error("not implemented")
end

function specific_heat_shomate(t, c::ShomateCoefs)
    c[1] + t * (c[2] + t * (c[3] + t * c[4])) + c[5] / t^2
end

function specific_heat_maierkelley(T, c::MaierKelleyCoefs)
    c[1] + c[2] * T + c[3] / T^2
end

function enthalpy_nasa(T, c::Nasa7Coefs)
    f = c[4] / 4 + T * c[5] / 5
    f = c[3] / 3 + T * f
    f = c[2] / 2 + T * f
    f = c[1] / 1 + T * f
    f = c[6] + T * f
    f
end

function enthalpy_nasa(T, c::Nasa9Coefs)
    error("not implemented")
end

function enthalpy_shomate(t, c::ShomateCoefs)
    p = t * (c[1] + t * (c[2]/2 + t * (c[3]/3 + t * c[4]/4)))
    p - c[5] / t + c[6] - c[8]
end

function enthalpy_maierkelley(T, c::MaierKelleyCoefs)
    T * (c[1] + c[2]/2 * T) - c[3] / T
end

function entropy_nasa(T, c::Nasa7Coefs)
    f = c[4] / 3 + T * c[5] / 4
    f = c[3] / 2 + T * f
    f = c[2] / 1 + T * f
    f = c[7] + c[1] * log(T) + T * f
    f
end

function entropy_nasa(T, c::Nasa9Coefs)
    error("not implemented")
end

function entropy_shomate(t, c::ShomateCoefs)
    p = log(t) * c[1] + t * (c[2] + t * (c[3]/2 + t * c[4]/3))
    p - c[5] / (2 * t^2) + c[7]
end

function entropy_maierkelley(T, c::MaierKelleyCoefs)
    log(T) * c[1] + c[2] * T - c[3] / (2 * T^2)
end

function properties_nasa(T, c)
    eval_cp = GAS_CONSTANT * specific_heat_nasa(T, c)
    eval_hm = GAS_CONSTANT * enthalpy_nasa(T, c)
    eval_sm = GAS_CONSTANT * entropy_nasa(T, c)
    eval_cp, eval_hm, eval_sm
end

function properties_shomate(T, c)
    eval_cp = specific_heat_shomate(T/1000, c)
    eval_hm = enthalpy_shomate(T/1000, c)
    eval_sm = entropy_shomate(T/1000, c)
    eval_cp, eval_hm, eval_sm
end

function properties_maierkelley(T, c)
    eval_cp = specific_heat_maierkelley(T, c)
    eval_hm = enthalpy_maierkelley(T, c)
    eval_sm = entropy_maierkelley(T, c)
    eval_cp, eval_hm, eval_sm
end
#endregion: thermo-parameterizations

#region: thermo
THERMO_WARNINGS = true

function disable_thermo_warnings()
    global THERMO_WARNINGS = false
    nothing
end

function enable_thermo_warnings()
    global THERMO_WARNINGS = true
    nothing
end

macro thermocoefs(data)
    return quote
        m = reduce(hcat, $(esc(data)))
        SMatrix{size(m)...}(m)
    end
end

"""
Generic storage of thermodynamic data with arbitrary sizes. This structure
is not associated to any specific thermodynamic model/representation.
"""
struct ThermoData{K, N, M}
    "Data matrix with `K` coefficients for `N` temperature ranges."
    params::SMatrix{K, N, Float64}

    "Temperature bounds for `N=M-1` intervals associated to data."
    bounds::NTuple{M, Float64}

    function ThermoData(params::SMatrix{K, N, Float64},
                        bounds::NTuple{M, Float64}) where {K, N, M}
        if M-1 != N
            error("""\
                Bounds size ($M) must be one more than the number of \
                provided coefficient ranges ($N). Please check your data.
                """)
        end

        if !issorted(bounds)
            error("""\
                Tuple of ranges `bounds` must be sorted: got $(bounds).
                """)
        end

        return new{K, N, M}(params, bounds)
    end

    function ThermoData(params::Vector{Vector{Float64}}, bounds::Vector{Float64})
        return ThermoData(@thermocoefs(params), Tuple(bounds))
    end
end

"""
Stores data for NASA-`K` parametrization with `N` temperature ranges.
"""
struct NASAThermo{K, N} <: AbstractThermodynamicData
    data::ThermoData{K, N}
    h_ref::Float64
    s_ref::Float64

    function NASAThermo(data::ThermoData{K, N}) where {K, N}
        # c = SVector{K}(data.params[1:end, 1])
        # h_ref = enthalpy_nasa(T_STANDARD, c)
        # s_ref = entropy_nasa(T_STANDARD, c)
        # return new{K, N}(data, h_ref, s_ref)
        return new{K, N}(data, data.params[end-1, 1], data.params[end, 1])
    end

    function NASAThermo(data::Vector{Vector{Float64}}, bounds::Vector{Float64})
        return NASAThermo(ThermoData(data, bounds))
    end
end

"""
Stores data for Shomate parametrization with `N` temperature ranges.
Model equations are based in the ideas of Shomate [Shomate1954](@cite).

**Note:** Shomate data provided in literature is often found in JANAF
tables which report values on a per mole basis.
"""
struct ShomateThermo{K, N} <: AbstractThermodynamicData
    data::ThermoData{K, N}
    h_ref::Float64
    s_ref::Float64

    function ShomateThermo(data::ThermoData{K, N}) where {K, N}
        return new{K, N}(data, data.params[end-1, 1], data.params[end, 1])
    end

    function ShomateThermo(data::Vector{Vector{Float64}}, bounds::Vector{Float64})
        return ShomateThermo(ThermoData(data, bounds))
    end
end

"""
Stores data for Maier-Kelley parametrization with `N` temperature ranges.
Model equations are based in the ideas of Maier and Kelley [Maier1932](@cite).

**Note:** Maier-Kelley data provided in literature is often provided in
calorie per mole units; convert to joules before providing it here!
"""
struct MaierKelleyThermo{K, N} <: AbstractThermodynamicData
    data::ThermoData{K, N}
    h_ref::Float64
    s_ref::Float64

    function MaierKelleyThermo(data::ThermoData{K, N}) where {K, N}
        return new{K, N}(data, data.params[end-1, 1], data.params[end, 1])
    end

    function MaierKelleyThermo(data::Vector{Vector{Float64}}, bounds::Vector{Float64})
        return MaierKelleyThermo(ThermoData(data, bounds))
    end
end

# struct MaierKelleyThermo <: AbstractThermodynamicData end
# struct EinsteinThermo <: AbstractThermodynamicData end

function factory_symbolic(data::ThermoData{K, N, M}, properties) where {K, N, M}
    @variables T

    jumps = data.bounds[1:N]
    coefs = data.params

    funs = properties(T, SVector{K}(coefs[1:end, 1]))
    fun_cp, fun_hm, fun_sm = funs

    for k in range(2, N)
        δ = heaviside(T, jumps[k])

        funs = properties(T, SVector{K}(coefs[1:end, k]))
        new_cp, new_hm, new_sm = funs

        Δcp = simplify(new_cp - fun_cp; expand = true)
        Δhm = simplify(new_hm - fun_hm; expand = true)
        Δsm = simplify(new_sm - fun_hm; expand = true)

        fun_cp += δ * Δcp
        fun_hm += δ * Δhm
        fun_sm += δ * Δsm
    end

    # XXX: this is producing identically zero results in some cases
    # for Shomate models of specific heat and entropy. Why? Probably
    # due to some overflow due to the T/1000 factor. Keep this note
    # as this is a weak point of the implementation. It was also
    # observed that this breaks the management of the heaviside
    # intended behavior.
    # fun_cp = simplify(fun_cp; expand = true)
    # fun_hm = simplify(fun_hm; expand = true)
    # fun_sm = simplify(fun_sm; expand = true)

    return fun_cp, fun_hm, fun_sm
end

function factory_symbolic(m::NASAThermo{K, N}) where {K, N}
    factory_symbolic(m.data, properties_nasa)
end

function factory_symbolic(m::ShomateThermo{K, N}) where {K, N}
    factory_symbolic(m.data, properties_shomate)
end

function factory_symbolic(m::MaierKelleyThermo{K, N}) where {K, N}
    factory_symbolic(m.data, properties_maierkelley)
end

function factory_numeric(m::NASAThermo{K, N}) where {K, N}
    error("not implemented")
end

function factory_numeric(m::ShomateThermo{K, N}) where {K, N}
    error("not implemented")
end

function factory_numeric(m::MaierKelleyThermo{K, N}) where {K, N}
    error("not implemented")
end

function thermo_models()
    Dict(
        :NASA7 => NASAThermo,
        :NASA9 => NASAThermo,
        :SHOMATE => ShomateThermo,
        :MAIERKELLEY => MaierKelleyThermo,
        # :EINSTEIN => EinsteinThermo,
    )
end

function get_thermo_model(name::String)
    name = uppercase(name)
    symb = Symbol(name)
    models = thermo_models()

    if !haskey(models, symb)
        error("""\
        Unknown thermodynamic model `$(name)`; model name must be \
        among the following: $(keys(models))
        """)
    end

    models[symb]
end

function thermo_data(; model, data, bounds)
    get_thermo_model(model)(data, bounds)
end

function thermo_factory(m::AbstractThermodynamicData; how = :symbolic)
    how == :symbolic && return factory_symbolic(m)
    how == :numeric  && return factory_numeric(m)

    # XXX: for now this seems better as error handling than trying
    # something as getfield(Module, Symbol("nasa7_$(how)"))(m)
    error("""\
        Unknown factory method $(how); currently supported values are \
        `:symbolic` and `:numeric`.
        """)
end

function thermo_factory(model::String, data, bounds; how = :symbolic)
    thermo_factory(thermo_data(; model, data, bounds); how)
end

# XXX: keep this wrapper for ease of data parsing!
function thermo_factory(; model, data, bounds, how = :symbolic)
    thermo_factory(model, data, bounds; how)
end

function compile_function(f, expression)
    build_function(f, Symbolics.get_variables(f); expression)
end

struct CompiledThermoFunctions
    specific_heat::Function
    enthalpy::Function
    entropy::Function

    function CompiledThermoFunctions(funcs; expression = Val{false})
        return new(compile_function.(funcs, expression)...)
    end
end

function CompiledThermoFunctions(model::String, data, bounds;
        how = :symbolic, expression = Val{false})
    funcs = thermo_factory(model, data, bounds; how)
    new(compile_function.(funcs, expression)...)
end
#endregion: thermo

#region: species
struct SpeciesMeta
    name::String
    display_name::String
    aggregation::String
    source::Union{Nothing, String}
    note::Union{Nothing, String}

    function SpeciesMeta(s::NamedTuple)
        return new(s.name, s.display_name, s.aggregation, s.source, s.note)
    end
end

struct Thermodynamics <: AbstractThermodynamicsModel
    data::AbstractThermodynamicData
    base::NTuple{3, Any}
    func::CompiledThermoFunctions
    h298::Float64
    s298::Float64

    function Thermodynamics(thermo::NamedTuple; how = :symbolic)
        data = thermo_data(; thermo...)
        base = thermo_factory(data; how)
        func = CompiledThermoFunctions(base)
        h298 = func.enthalpy(298.15)
        s298 = func.entropy(298.15)
        return new(data, base, func, h298, s298)
    end
end

struct Species
    meta::SpeciesMeta
    composition::ChemicalComponent
    thermo::AbstractThermodynamicsModel
    transport::Union{Nothing, AbstractTransportModel}

    function Species(s::NamedTuple; how = :symbolic)
        meta = SpeciesMeta(s)
        comp = component(s.composition)
        thermo = Thermodynamics(s.thermo; how)

        # TODO: implement transport model!
        trans = nothing

        return new(meta, comp, thermo, trans)
    end
end

function Species(s::Dict)
	return Species(parsespeciesyaml(s))
end

function molar_mass(s::Species)
    return 0.001s.composition.molar_mass
end

function specific_heat(s::Species, T)
    return specific_heat_mole(s, T) / molar_mass(s)
end

function enthalpy(s::Species, T)
    return enthalpy_mole(s, T) / molar_mass(s)
end

function entropy(s::Species, T)
    return entropy_mole(s, T) / molar_mass(s)
end

function formation_enthalpy(s::Species)
    return s.thermo.data.h_ref
end

function specific_heat_mole(s::Species, T)
    return s.thermo.func.specific_heat(T)
end

function enthalpy_mole(s::Species, T)
    return s.thermo.func.enthalpy(T)
end

function entropy_mole(s::Species, T)
    return s.thermo.func.entropy(T)
end

# WIP: enthalpy calculation for use in Hess' law [J/mol].
function enthalpy_hess(s, T; T_ref = nothing)
    h_ref = isnothing(T_ref) ? s.thermo.h298 : enthalpy_mole(s, T_ref)
    return (enthalpy_mole(s, T) - h_ref) + formation_enthalpy(s)
end

function enthalpy_reaction(T, vr, vp, r, p)
    hr = vr' * map(s->enthalpy_hess(s, T), r)
    hp = vp' * map(s->enthalpy_hess(s, T), p)
    return hp - hr
end
#endregion: species

#region: database
"Name of default project thermodynamics database."
const THERMO_COMPOUND_DATA = "auchimiste.yaml"

struct AuChimisteDatabase
    description::String
    species::NamedTuple
    references::Union{Nothing, Dict{String, String}}
end

function AuChimisteDatabase(;
        data_file::String = THERMO_COMPOUND_DATA,
        selected_species::Union{String, Vector{String}} = "*",
        validate::Bool = true, which::Bool = false
    )
    data = loaddatayaml(data_file; which)

    if validate && !validatedatabase(data)
        throw(ErrorException("Unable to validate $(data_file)"))
    end

    species = getselectedspecies(data["species"], selected_species)
    species = NamedTuple(map(s->Symbol(s.meta.name)=>s, species))

    AuChimisteDatabase(
        replace(data["description"], "\n"=>" "),
        species,
        get(data, "references", nothing)
    )
end

function loaddatayaml(fname; kwargs...)
    which = get(kwargs, :which, false)
    path = finddatafile(fname; which)
    YAML.load_file(path)
end

function finddatafile(name; which = false)
    if isabspath(name) && isfile(name)
        which && @info("Absolute path provided for `$(name)`")
        return name
    end

    for path in USER_PATH
        tentative = joinpath(path, name)

        if isfile(tentative)
            which && @info("Data file `$(name)` found at `$(path)`")
            return tentative
        end
    end

    path = join(map(n->"- $(n)", USER_PATH), "\n")
    @warn("Data file `$(name)` not in load path:\n$(path)")

    nothing
end

function validatedatabase(data)
    !haskey(data, "species") && begin
        @warn("Missing `species` section in thermodata!")
    end

    !haskey(data, "references") && begin
        @warn("Missing `references` section in thermodata!")
    end

    refs = get(data, "references", nothing)
    spec = get(data, "species", nothing)

    isnothing(spec) && return false

    if !isnothing(refs) && !all(c->validatereference(c, refs), spec)
        return false
    end

    @warn("Cannot validate references: not available")
    true
end

function validatereference(species, refs)
    !haskey(species, "data_source") && begin
        @warn("Missing data source for $(species["name"])")
        return false
    end

    !haskey(refs, species["data_source"]) && begin
        @warn("Missing reference entry for $(species["data_source"])")
        return false
    end

    true
end

function getselectedspecies(species, selected)
    selected == "*" && return Species.(species)
    Species.(filter(c->c["name"] in selected, species))
end

function parsethermoyaml(thermo)
    model = thermo["model"]
    bounds = get(thermo, "temperature-ranges", [0.0, 6000.0])
    data = thermo["data"]

    # XXX: add units to database!
    if uppercase(model) == "MAIERKELLEY"
        data .*= JOULE_PER_CALORIE
    end

    return (; model, bounds, data)
end

function parsetransportyaml(trans)
    isnothing(trans) && return nothing

    model = trans["model"]
    geometry = trans["geometry"]
    well_depth = trans["well-depth"]
    diameter = trans["diameter"]

    rot_relaxation = get(trans, "rotational-relaxation", nothing)
    polarizability = get(trans, "polarizability", nothing)
    dipole = get(trans, "dipole", nothing)
    note = get(trans, "note", nothing)

    return (;
        model,
        geometry,
        well_depth,
        diameter,
        rot_relaxation,
        polarizability,
        dipole,
        note
    )
end

function parsespeciesyaml(species)
    name = species["name"]
    display_name = get(species, "display_name", name)
    aggregation = get(species, "aggregation", "unknown")

    composition = species["composition"]
    thermo = parsethermoyaml(species["thermo"])
    transport = parsetransportyaml(get(species, "transport", nothing))
    source = get(species, "data_source", nothing)
    note = get(species, "note", nothing)

    return (;
        name,
        display_name,
        aggregation,
        composition,
        thermo,
        transport,
        source,
        note
    )
end

function speciesnames(data::AuChimisteDatabase)
    return String.(keys(data.species))
end

function speciestable(data::AuChimisteDatabase)
	species_meta = map(s->s.meta, values(data.species))
	columnize(n) = vcat(map(x->getfield(x, n), species_meta)...)

    return DataFrame(
        names   = columnize(:name),
        display = columnize(:display_name),
        source  = columnize(:source),
        state   = columnize(:aggregation)
	)
end

# XXX: lazy loading (database not really parsed, just the names)
function listspecies(; data_file = THERMO_COMPOUND_DATA, which = false)
    data = load_data_yaml(data_file; which)
    return map(c->c["name"], data["species"])
end
#endregion: database

end # (module AuChimiste)