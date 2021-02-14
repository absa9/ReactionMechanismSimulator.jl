using DiffEqBase
import DiffEqBase: AbstractODESolution, HermiteInterpolation,AbstractDiffEqInterpolation
using DiffEqSensitivity
using ForwardDiff

abstract type AbstractSimulation end
export AbstractSimulation

struct Simulation{Q<:AbstractODESolution,W<:AbstractDomain,L<:AbstractArray,G<:Function,G2<:AbstractArray} <: AbstractSimulation
    sol::Q
    domain::W
    names::L
    N::G
    Ns::G2
end

function Simulation(sol::Q,domain::W) where {Q<:AbstractODESolution,W<:AbstractDomain}
    names = getfield.(domain.phase.species,:name)
    Ns = sum(hcat(sol.interp.u...)[domain.indexes[1]:domain.indexes[2],:],dims=1)
    Nderivs = sum(hcat(sol.interp.du...)[domain.indexes[1]:domain.indexes[2],:],dims=1)
    N = HermiteInterpolation(sol.interp.t,Ns,Nderivs)
    F(t::T) where {T<:Real} = N(t,nothing,Val{0},sol.prob.p,:left)
    return Simulation(sol,domain,names,F,Ns)
end

export Simulation

struct SystemSimulation{Q,B<:AbstractODESolution,X,Y,Z}
    sol::B
    sims::Q
    interfaces::X
    names::Array{String,1}
    species::Array{Z,1}
    reactions::Array{Y,1}
    p::Array{Float64,1}
end

function SystemSimulation(sol,domains,interfaces,p)
    sims = Tuple([Simulation(sol,domain) for domain in domains])
    names = Array{String,1}()
    reactions = Array{ElementaryReaction,1}()
    species = Array{Species,1}()
    for sim in sims
        append!(names,sim.names)
        append!(species,sim.domain.phase.species)
        append!(reactions,sim.domain.phase.reactions)
    end
    for inter in interfaces
        if hasproperty(inter,:reactions)
            append!(reactions,inter.reactions)
        end
    end
    return SystemSimulation(sol,sims,interfaces,names,species,reactions,p)
end
export SystemSimulation

length(p::T) where {T<:AbstractSimulation} = 1
export length

iterate(p::T) where {T<:AbstractSimulation} = p
export iterate

Broadcast.broadcastable(p::T) where {T<:AbstractSimulation} = Ref(p)
export broadcastable

spcindex(bsol::Z,name::Q) where {Z<:Simulation,Q<:AbstractString} = findfirst(isequal(name),getfield.(bsol.domain.phase.species,:name))
export spcindex

function molefractions(bsol::Q,name::W,t::E) where {Q<:AbstractSimulation, W<:String, E<:Real}
    @assert name in bsol.names
    ind = findfirst(isequal(name),bsol.names)+bsol.domain.indexes[1]-1
    return bsol.sol(t)[ind]/bsol.N(t)
end

function molefractions(bsol::Q, t::E) where {Q<:AbstractSimulation,E<:Real}
    return bsol.sol(t)[bsol.domain.indexes[1]:bsol.domain.indexes[2]]./bsol.N(t)
end

function molefractions(bsol::Q) where {Q<:AbstractSimulation}
    @views return hcat(bsol.sol.u...)[bsol.domain.indexes[1]:bsol.domain.indexes[2],:]./bsol.Ns
end

export molefractions

getT(bsol::Simulation{Q,W,L,G}, t::K) where {W<:Union{ConstantTPDomain,ConstantTVDomain},K<:Real,Q,G,L} = bsol.domain.T
getT(bsol::Simulation{Q,W,L,G}, t::K) where {W<:Union{ConstantVDomain,ParametrizedVDomain,ConstantPDomain,ParametrizedPDomain},K<:Real,Q,G,L} = bsol.sol(t)[bsol.domain.indexes[3]]
getT(bsol::Simulation{Q,W,L,G}, t::K) where {W<:Union{ParametrizedTConstantVDomain,ParametrizedTPDomain},K<:Real,Q,G,L} = bsol.domain.T(t)
export getT
getV(bsol::Simulation{Q,W,L,G}, t::K) where {W<:Union{ConstantVDomain,ConstantTVDomain,ParametrizedTConstantVDomain},K<:Real,Q,G,L} = bsol.domain.V
getV(bsol::Simulation{Q,W,L,G}, t::K) where {W<:ParametrizedVDomain,K<:Real,Q,G,L} = bsol.domain.V(t)
getV(bsol::Simulation{Q,W,L,G}, t::K) where {W<:Union{ConstantTPDomain,ParametrizedTPDomain},K<:Real,Q,G,L} = bsol.sol(t)[bsol.domain.indexes[3]]
getV(bsol::Simulation{Q,W,L,G}, t::K) where {W<:Union{ParametrizedPDomain,ConstantPDomain},K<:Real,Q,G,L} = bsol.sol(t)[bsol.domain.indexes[4]]
export getV
getP(bsol::Simulation{Q,W,L,G}, t::K) where {W<:Union{ConstantTPDomain,ConstantPDomain},K<:Real,Q,G,L} = bsol.domain.P
getP(bsol::Simulation{Q,W,L,G}, t::K) where {W<:Union{ConstantTVDomain,ParametrizedTConstantVDomain},K<:Real,Q,G,L} = 1.0e6
getP(bsol::Simulation{Q,W,L,G}, t::K) where {W<:Union{ParametrizedTPDomain,ParametrizedPDomain},K<:Real,Q,G,L} = bsol.domain.P(t)
getP(bsol::Simulation{Q,W,L,G}, t::K) where {W<:Union{ConstantVDomain, ParametrizedVDomain},K<:Real,Q,G,L} = bsol.sol(t)[bsol.domain.indexes[4]]
export getP
getC(bsol::Simulation{Q,W,L,G}, t::K) where {W<:ConstantTPDomain,K<:Real,Q,G,L} = bsol.domain.P/(R*bsol.domain.T)
getC(bsol::Simulation{Q,W,L,G}, t::K) where {W<:Union{ConstantVDomain,ConstantTVDomain,ParametrizedTConstantVDomain},K<:Real,Q,G,L} = bsol.N(t)/bsol.domain.V
getC(bsol::Simulation{Q,W,L,G}, t::K) where {W<:ParametrizedVDomain,K<:Real,Q,G,L} = bsol.N(t)/bsol.domain.V(t)
getC(bsol::Simulation{Q,W,L,G}, t::K) where {W<:ParametrizedTPDomain,K<:Real,Q,G,L} = bsol.domain.P(t)/(R*bsol.domain.T(t))
getC(bsol::Simulation{Q,W,L,G}, t::K) where {W<:ConstantPDomain,K<:Real,Q,G,L} = bsol.domain.P/(R*getT(bsol,t))
getC(bsol::Simulation{Q,W,L,G}, t::K) where {W<:ParametrizedPDomain,K<:Real,Q,G,L} = bsol.domain.P(t)/(R*getT(bsol,t))
export getC
"""
calculates the rates of production/loss at a given time point
this outputs a sparse matrix of  num reactions xnum species containing the production/loss
rate of that species associated with that reaction
"""
function rops(bsol::Q,t::X) where {Q<:Simulation,X<:Real}
    ropmat = zeros(length(bsol.domain.phase.reactions),length(bsol.domain.phase.species))
    cs,kfs,krevs = calcthermo(bsol.domain,bsol.sol(t),t)[[2,9,10]]
    @simd for i in 1:length(bsol.domain.phase.reactions)
        rxn = bsol.domain.phase.reactions[i]
        R = getrate(rxn,cs,kfs,krevs)
        for ind in rxn.productinds
            ropmat[i,ind] += R
        end
        for ind in rxn.reactantinds
            ropmat[i,ind] -= R
        end
    end
    return ropmat
end

"""
calculates the rates of production/loss at a given time point for a single species
this outputs a sparse vector of length num reactions containing the production/loss
rate associated with that reaction for the given species
"""
function rops(bsol::Y,name::X,t::Z) where {Y<:Simulation, X<:AbstractString, Z<:Real}
    rop = spzeros(length(bsol.domain.phase.reactions))
    cs,kfs,krevs = calcthermo(bsol.domain,bsol.sol(t),t)[[2,9,10]]
    ind = findfirst(isequal(name),getfield.(bsol.domain.phase.species,:name))
    @assert !isa(ind,Nothing) "species $name not in species array"
    for (i,rxn) in enumerate(bsol.domain.phase.reactions)
        c = 0
        R = getrate(rxn,cs,kfs,krevs)
        c -= count(isequal(ind),rxn.reactantinds)
        c += count(isequal(ind),rxn.productinds)
        if c != 0
            rop[i] = c*R
        end
    end
    return rop
end
export rops

"""
Calculates sensitivities with respect to `target` at the time point at the end of the simulation
The returned sensitivities are the normalized values

By default uses the InterpolatingAdjoint algorithm with vector Jacobian products calculated with ReverseDiffVJP(true)
this assumes no changes in code branching during simulation, if that were to become no longer true, the Tracker 
based alternative algorithm is slower, but avoids this concern. 
"""
function getadjointsensitivities(bsol::Q,target::String,solver::W;sensalg::W2=InterpolatingAdjoint(autojacvec=ReverseDiffVJP(false)),abstol::Float64=1e-6,reltol::Float64=1e-3,kwargs...) where {Q,W,W2}
    @assert target in bsol.names || target in ["T","V","P"]
    if target in ["T","V","P"]
        if haskey(bsol.domain.thermovariabledict, target)
            ind = bsol.domain.thermovariabledict[target]
        else
            throw(error("$(bsol.domain) doesn't have $target in its thermovariables"))
        end
    else
        ind = findfirst(isequal(target),bsol.names)
        sensdomain,sensspcnames,senstooriginspcind,senstooriginrxnind = getsensdomain(bsol.domain,ind)
        if :thermovariabledict in fieldnames(typeof(bsol.domain))
            yinds = vcat(senstooriginspcind,collect(values(bsol.domain.thermovariabledict)))
        else
            yinds = vcat(senstooriginspcind)
        end
        pinds = vcat(senstooriginspcind,length(bsol.domain.phase.species).+senstooriginrxnind)
        ind = findfirst(isequal(target),sensspcnames)
    end
    
    function sensg(y::X,p::Array{Y,1},t::Z) where {Q,V,X,Y<:Float64,Z}
        sensy = y[yinds]
        sensp = p[pinds]
        dy = similar(sensy,length(sensy))
        return dydtreactor!(dy,sensy,t,sensdomain,[],p=sensp)[ind]
    end
    function sensg(y::Array{X,1},p::Y,t::Z) where {Q,V,X<:Float64,Y,Z} 
        sensy = y[yinds]
        sensp = p[pinds]
        dy = similar(sensp,length(sensy))
        return dydtreactor!(dy,sensy,t,sensdomain,[],p=sensp)[ind]
    end
    function sensg(y::Array{X,1},p::Array{Y,1},t::Z) where {Q,V,X<:Float64,Y<:Float64,Z} 
        sensy = y[yinds]
        sensp = p[pinds]
        dy = similar(sensy,length(sensy))
        return dydtreactor!(dy,sensy,t,sensdomain,[],p=sensp)[ind]
    end
    function sensg(y::Array{X,1},p::Array{Y,1},t::Z) where {Q,V,X<:ForwardDiff.Dual,Y<:ForwardDiff.Dual,Z} 
        sensy = y[yinds]
        sensp = p[pinds]
        dy = similar(sensy,length(sensy))
        return dydtreactor!(dy,sensy,t,sensdomain,[],p=sensp)[ind]
    end
    
    function g(y::X,p::Array{Y,1},t::Z) where {Q,V,X,Y<:Float64,Z} 
        dy = similar(y,length(y))
        return dydtreactor!(dy,y,t,bsol.domain,[],p=p)[ind]
    end
    function g(y::Array{X,1},p::Y,t::Z) where {Q,V,X<:Float64,Y,Z} 
        dy = similar(p,length(y))
        return dydtreactor!(dy,y,t,bsol.domain,[],p=p)[ind]
    end
    function g(y::Array{X,1},p::Array{Y,1},t::Z) where {Q,V,X<:Float64,Y<:Float64,Z} 
        dy = zeros(length(y))
        return dydtreactor!(dy,y,t,bsol.domain,[],p=p)[ind]
    end
    function g(y::Array{X,1},p::Array{Y,1},t::Z) where {Q,V,X<:ForwardDiff.Dual,Y<:ForwardDiff.Dual,Z} 
        dy = similar(y,length(y))
        return dydtreactor!(dy,y,t,bsol.domain,[],p=p)[ind]
    end

    dsensgdu(out, y, p, t) = ForwardDiff.gradient!(out, y -> sensg(y, p, t), y)
    dsensgdp(out, y, p, t) = ForwardDiff.gradient!(out, p -> sensg(y, p, t), p)
    dgdu(out, y, p, t) = ForwardDiff.gradient!(out, y -> g(y, p, t), y)
    dgdp(out, y, p, t) = ForwardDiff.gradient!(out, p -> g(y, p, t), p)
    dsensgdurevdiff(out, y, p, t) = ReverseDiff.gradient!(out, y -> sensg(y, p, t), y)
    dsensgdprevdiff(out, y, p, t) = ReverseDiff.gradient!(out, p -> sensg(y, p, t), p)
    dgdurevdiff(out, y, p, t) = ReverseDiff.gradient!(out, y -> g(y, p, t), y)
    dgdprevdiff(out, y, p, t) = ReverseDiff.gradient!(out, p -> g(y, p, t), p)
    
    pethane = 160
    if length(bsol.domain.p)<= pethane
        if target in ["T","V","P"]
            du0,dpadj = adjoint_sensitivities(bsol.sol,solver,g,nothing,(dgdu,dgdp);sensealg=sensalg,abstol=abstol,reltol=reltol,kwargs...)
        else
            du0,dpadj = adjoint_sensitivities(bsol.sol,solver,sensg,nothing,(dsensgdu,dsensgdp);sensealg=sensalg,abstol=abstol,reltol=reltol,kwargs...)
        end
    else
        if target in ["T","V","P"]
            du0,dpadj = adjoint_sensitivities(bsol.sol,solver,g,nothing,(dgdurevdiff,dgdprevdiff);sensealg=sensalg,abstol=abstol,reltol=reltol,kwargs...)
        else
            du0,dpadj = adjoint_sensitivities(bsol.sol,solver,sensg,nothing,(dsensgdurevdiff,dsensgdprevdiff);sensealg=sensalg,abstol=abstol,reltol=reltol,kwargs...)
        end
    end
    dpadj[length(bsol.domain.phase.species)+1:end] .*= bsol.domain.p[length(bsol.domain.phase.species)+1:end]
    if !(target in ["T","V","P"])
        dpadj ./= bsol.sol(bsol.sol.t[end])[senstooriginspcind[ind]]
    end
    return dpadj
end
export getadjointsensitivities

function getconcentrationsensitivity(bsol::Simulation{Q,W,L,G}, numerator::String, denominator::String, t::K) where {W<:Union{ConstantVDomain,ConstantTVDomain,ParametrizedTConstantVDomain},K<:Real,Q,G,L}
    @assert numerator in bsol.names
    @assert denominator in bsol.names
    indnum = findfirst(isequal(numerator),bsol.names)+bsol.domain.indexes[1]-1
    inddeno = findfirst(isequal(denominator),bsol.names)+bsol.domain.parameterindexes[1]-1
    Nvars = length(bsol.domain.phase.species)+length(bsol.domain.indexes)-2 
    Nrxns = length(bsol.domain.phase.reactions)
    x,dp = extract_local_sensitivities(bsol.sol,t)
    s = dp[inddeno][indnum]
    val = s/bsol.sol(t)[indnum] #constant volume
    if t == 0
        return 0.0
    else
        return val
    end
end

function getconcentrationsensitivity(bsol::Simulation{Q,W,L,G}, numerator::String, denominator::String, t::K) where {W<:Union{ConstantTPDomain,ParametrizedTPDomain,ConstantPDomain,ParametrizedPDomain,ParametrizedVDomain},K<:Real,Q,G,L}
    @assert numerator in bsol.names
    @assert denominator in bsol.names
    indnum = findfirst(isequal(numerator),bsol.names)+bsol.domain.indexes[1]-1
    inddeno = findfirst(isequal(denominator),bsol.names)+bsol.domain.parameterindexes[1]-1
    Nvars = length(bsol.domain.phase.species)+length(bsol.domain.indexes)-2 
    Nrxns = length(bsol.domain.phase.reactions)
    x,dp = extract_local_sensitivities(bsol.sol,t)
    svals = dp[inddeno][bsol.domain.indexes[1]:bsol.domain.indexes[2]]
    s = svals[indnum]
    V = getV(bsol,t)
    c = bsol.sol(t)[indnum]/V
    val =  (s-c*sum(svals)*R*getT(bsol,t)/getP(bsol,t))/(c*V) #known T and P
    if t == 0
        return 0.0
    else
        return val
    end
end

function getconcentrationsensitivity(bsol::Simulation{Q,W,L,G}, numerator::String, denominator::Z, t::K) where {W<:Union{ConstantVDomain,ConstantTVDomain,ParametrizedTConstantVDomain},K<:Real,Z<:Integer,Q,G,L}
    @assert numerator in bsol.names
    indnum = findfirst(isequal(numerator),bsol.names)+bsol.domain.indexes[1]-1
    inddeno = denominator+bsol.domain.parameterindexes[1]-1
    Nvars = length(bsol.domain.phase.species)+length(bsol.domain.indexes)-2 
    Nrxns = length(bsol.domain.phase.reactions)
    x,dp = extract_local_sensitivities(bsol.sol,t)
    s = dp[inddeno+length(bsol.domain.phase.species)][indnum]
    T = getT(bsol,t)
    P = getP(bsol,t)
    C = getC(bsol,t)
    k = bsol.domain.p[inddeno+length(bsol.domain.phase.species)]
    val = s*k/bsol.sol(t)[indnum] #constant volume
    if t == 0
        return 0.0
    else
        return val
    end
end

function getconcentrationsensitivity(bsol::Simulation{Q,W,L,G}, numerator::String, denominator::Z, t::K) where {W<:Union{ConstantTPDomain,ParametrizedTPDomain,ConstantPDomain,ParametrizedPDomain,ParametrizedVDomain},K<:Real,Z<:Integer,Q,G,L}
    @assert numerator in bsol.names
    indnum = findfirst(isequal(numerator),bsol.names)+bsol.domain.indexes[1]-1
    inddeno = denominator+bsol.domain.parameterindexes[1]-1
    Nvars = length(bsol.domain.phase.species)+length(bsol.domain.indexes)-2 
    Nrxns = length(bsol.domain.phase.reactions)
    x,dp = extract_local_sensitivities(bsol.sol,t)
    svals = dp[inddeno+length(bsol.domain.phase.species)][bsol.domain.indexes[1]:bsol.domain.indexes[2]]
    s = svals[indnum]
    V = getV(bsol,t)
    T = getT(bsol,t)
    P = getP(bsol,t)
    C = getC(bsol,t)
    c = bsol.sol(t)[indnum]/V
    k = bsol.domain.p[inddeno+length(bsol.domain.phase.species)]
    val = k*(s-c*sum(svals)*R*T/P)/(c*V) #known T and P
    if t == 0
        return 0.0
    else
        return val
    end
end

export getconcentrationsensitivity

"""
calculate the rates of all reactions at time t
"""
function rates(bsol::Q,t::X) where {Q<:Simulation,X<:Real}
    cs,kfs,krevs = calcthermo(bsol.domain,bsol.sol(t),t)[[2,9,10]]
    return [getrate(rxn,cs,kfs,krevs) for rxn in bsol.domain.phase.reactions]
end

"""
calculate the rates of all reactions at given times ts
defaults to using bsol.sol.t if ts is not supplied
"""
function rates(bsol::Q;ts::X=Array{Float64,1}()) where {Q<:Simulation,X<:AbstractArray}
    if length(ts) == 0
        ts = bsol.sol.t
    end
    return hcat([rates(bsol,t) for t in ts]...)
end

export rates
