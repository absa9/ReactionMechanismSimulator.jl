using Parameters
include("./Calculators.jl")

abstract type AbstractSpecies

@with_kw struct Species{T<:AbstractThermo,N<:AbstractDiffusion} <: AbstractSpecies
    name::String
    index::Integer
    inchi::String = ""
    smiles::String = ""
    thermo::T
    diffusion::N = EmptyDiffusivity()
end
