using Random

export mads

"""
    mads(nlp)

MADS is implemented following the description of

    Mark A. Abramson, Charles Audet, J. E. Dennis Jr., and Sébastien Le Digabel.
    OrthoMADS: A Deterministic MADS Instance with Orthogonal Directions.
    SIAM Journal on Optimization, 2009, Vol. 20, No. 2, pp. 948-966,

But using random vectors instead of Halton vectors, as suggested by Francisco Sobral.
"""
function mads(nlp :: AbstractNLPModel;
              x :: AbstractVector=copy(nlp.meta.x0),
              atol :: Real=√eps(eltype(x)),
              rtol :: Real=√eps(eltype(x)),
              max_eval :: Int=nlp.meta.nvar*200,
              max_time :: Float64=30.0,
              max_iter :: Int=-1,
              stop_with_small_step :: Bool=false,
              steptol :: Real=1e-8,
              greedy :: Bool=false,
             )

  T = eltype(x)
  f(x) = obj(nlp, x)

  # TODO: Use a filter
  P(x) = if unconstrained(nlp)
    zero(eltype(x))
  else
    bl, bu, cl, cu = [getfield(nlp.meta, f) for f in [:lvar,:uvar,:lcon,:ucon]]
    p = sum(max(zero(T), x[i] - bu[i], bl[i] - x[i])^2 for i = 1:nlp.meta.nvar)
    if nlp.meta.ncon > 0
      cx = cons(nlp, x)
      p += sum(max(zero(T), cx[i] - cu[i], cl[i] - cx[i])^2 for i = 1:nlp.meta.ncon)
    end
    p
  end

  n = nlp.meta.nvar

  fx = f(x)
  Px = P(x)
  ftol = atol + abs(fx) * rtol

  Δ = min(one(T), minimum(nlp.meta.uvar - nlp.meta.lvar) / 10)
  μ = one(T)
  ϕx = fx + μ * Px
  Δmin = eps(T)

  iter = 0
  start_time = time()
  elapsed_time = 0.0
  tired = neval_obj(nlp) ≥ max_eval ≥ 0 || elapsed_time > max_time || iter > max_iter ≥ 0
  ∂f = Inf
  satisfied = stop_with_small_step && Δ ≤ steptol

  seq = 0

  xt = similar(x)

  q = randn(n)
  # Dk = [Hk -Hk]
  # Hk = qᵀq I - 2 qqᵀ
  # Hk eⱼ = qᵀq eⱼ - 2 qᵀeⱼ q = qᵀq eⱼ - 2qⱼ q

  # TODO: Use SolverTools log
  @info log_header([:iter, :nf, :f, :P, :Δ, :μ, :status], [Int, Int, T, T, T, T, String],
                   hdr_override=Dict(:f=>"f(x)", :P=>"P(x)"))

  @info log_row(Any[iter, neval_obj(nlp), fx, Px, Δ, μ])

  while !(satisfied || tired)
    decrease = false
    status = "No decrease"
    besti = 0
    bestf, bestP, bestϕ = fx, Px, ϕx
    #∂f = 0.0
    for s = [1, -1], i = 1:n
      xt .= x .- (2s * Δ * q[i]) .* q
      xt[i] += dot(q, q) * s * Δ
      ft = f(xt)
      Pt = P(xt)
      ϕt = ft + μ * Pt
      #∂f = max(∂f, abs(ft - fx) / Δ)
      if ϕt < bestϕ
        decrease = true
        status = "Decrease at i = $i, s = $s"
        besti = s * i
        bestf, bestP, bestϕ = ft, Pt, ϕt
        greedy || break
      end
    end
    if decrease
      fx, Px = bestf, bestP
      i = abs(besti)
      s = sign(besti)
      x .-= (2s * Δ * q[i]) .* q
      x[i] += dot(q, q) * s * Δ
      seq = max(seq + 1, 1)
      Δ *= T(4)^seq
    else
      seq = min(seq - 1, -1)
      Δ /= T(2)^(-1 / seq)
      if Px > 0
        μ = min(2μ, 1 / eps(T))
      end
    end
    iter += 1
    if !stop_with_small_step
      Δ = max(Δmin, Δ)
    end

    @info log_row(Any[iter, neval_obj(nlp), fx, Px, Δ, μ, status])

    randn!(q)
    ϕx = fx + μ * Px

    satisfied = (stop_with_small_step && Δ ≤ steptol) || (!decrease && ∂f ≤ ftol)
    elapsed_time = time() - start_time
    tired = neval_obj(nlp) ≥ max_eval ≥ 0 || elapsed_time > max_time || iter > max_iter ≥ 0
  end

  status = if Δ ≤ steptol
    :small_step
  elseif ∂f ≤ ftol
    :stalled
  elseif tired
    if neval_obj(nlp) ≥ max_eval ≥ 0
      :max_eval
    elseif elapsed_time > max_time
      :max_time
    else
      :max_iter
    end
  else
    :unknown
  end

  return GenericExecutionStats(status, nlp, solution=x, objective=fx, primal_feas=Px,
                               iter=iter, elapsed_time=elapsed_time)
end
