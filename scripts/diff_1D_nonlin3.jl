const USE_GPU = false
using ParallelStencil
using ParallelStencil.FiniteDifferences1D
@static if USE_GPU
    @init_parallel_stencil(CUDA, Float64, 1)
else
    @init_parallel_stencil(Threads, Float64, 1)
end
using Plots, Printf, LinearAlgebra

macro innH3()    esc(:( @inn(H) * @inn(H) * @inn(H)          )) end
macro avH3()     esc(:( @av(H) * @av(H) * @av(H)             )) end
macro avRe()     esc(:( π + sqrt(π^2 + lx^2 / @avH3() / dt)  )) end
macro Re()       esc(:( π + sqrt(π^2 + lx^2 / @innH3() / dt) )) end
macro τr_dt()    esc(:( lx / Vpdt / @avRe()                  )) end
macro dt_ρ()     esc(:( Vpdt * lx / @innH3() / @Re()         )) end

@parallel function compute_flux!(qHx, qHx2, H, Vpdt, dt, lx, dx)
    @all(qHx)  = (@all(qHx) * @τr_dt() - @avH3() * @d(H) / dx) / (1.0 + @τr_dt())
    @all(qHx2) = -@avH3() * @d(H) / dx
    return
end

@parallel function compute_update!(H, Hold, qHx, Vpdt, dt, lx, dx)
    @inn(H) = (@inn(H) +  @dt_ρ() * (@inn(Hold) / dt - @d(qHx) / dx)) / (1.0 + @dt_ρ() / dt)
    return
end

@parallel function check_res!(ResH, H, Hold, qHx2, dt, dx)
    @inn(ResH) = -(@inn(H) - @inn(Hold)) / dt - @d(qHx2) / dx
    return
end

@views function diffusion_1D(; nx=512, do_viz=false)
    # Physics
    lx     = 10.0       # domain size
    ttot   = 1.0        # total simulation time
    dt     = 0.2        # physical time step
    # Numerics
    # nx     = 2*256      # numerical grid resolution
    tol    = 1e-8       # tolerance
    itMax  = 1e5        # max number of iterations
    nout   = 10         # tol check
    CFL    = 1.0        # CFL number
    # Derived numerics
    dx     = lx / nx      # grid size
    Vpdt   = CFL * dx
    xc     = LinRange(dx / 2, lx - dx / 2, nx)
    # Array allocation
    qHx    = @zeros(nx - 1)
    qHx2   = @zeros(nx - 1)
    ResH   = @zeros(nx - 2)
    # Initial condition
    H0     = Data.Array(exp.(-(xc .- lx / 2).^2))
    Hold   = @ones(nx) .* H0
    H      = @ones(nx) .* H0
    t = 0.0; it = 0; ittot = 0; nt = ceil(ttot / dt)
    # Physical time loop
    while it < nt
        iter = 0; err = 2 * tol
        # Pseudo-transient iteration
        while err > tol && iter < itMax
            @parallel compute_flux!(qHx, qHx2, H, Vpdt, dt, lx, dx)
            @parallel compute_update!(H, Hold, qHx, Vpdt, dt, lx, dx)
            iter += 1
            if iter % nout == 0
                @parallel check_res!(ResH, H, Hold, qHx2, dt, dx)
                err = norm(ResH) / length(ResH)
            end
        end
        ittot += iter; it += 1; t += dt
        Hold .= H
        if isnan(err) error("NaN") end
    end
    @printf("Total time = %1.2f, time steps = %d, nx = %d, iterations tot = %d \n", round(ttot, sigdigits=2), it, nx, ittot)
    # Visualise
    if do_viz plot(xc, Array(H0), linewidth=3); display(plot!(xc, Array(H), legend=false, framestyle=:box, linewidth=3, xlabel="lx", ylabel="H", title="nonlinear diffusion (nt=$it, iters=$ittot)")) end
    return nx, ittot
end

diffusion_1D(; nx=512, do_viz=true)