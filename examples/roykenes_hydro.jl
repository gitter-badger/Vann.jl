# Required packages

using Vann
using PyPlot
using DataFrames

# Model choices

hydro_choice = Gr4j

# Load data

path_inputs = Pkg.dir("Vann", "data/roykenes")

date, tair, prec, q_obs, frac = load_data(path_inputs)

q_obs[q_obs .< 0] = NaN

prec = sum(prec, 1)

tair = mean(tair, 1)

# Compute potential evapotranspiration

epot = epot_monthly(date)

# Initilize model

tstep = 3/24


epot = epot * tstep


st_hydro = eval(Expr(:call, hydro_choice, tstep))

# Run calibration

param_hydro = run_model_calib(st_hydro, prec, epot, q_obs)

println(param_hydro)

# Reinitilize model

st_hydro = eval(Expr(:call, hydro_choice, tstep, param_hydro))

# Run model with best parameter set

q_sim = run_model(st_hydro, prec, epot)

# Store results in data frame

q_obs = round(q_obs, 2)
q_sim = round(q_sim, 2)

df_res = DataFrame(date = date, q_sim = q_sim, q_obs = q_obs)

# Compute performance

perf_nse = nse(df_res[:q_sim], df_res[:q_obs])
perf_nse = round(perf_nse, 2)

perf_kge = kge(df_res[:q_sim], df_res[:q_obs])
perf_kge = round(perf_kge, 2)

# Plot results using rcode

fig = plt[:figure](figsize = (12,7))

plt[:style][:use]("ggplot")

plt[:plot](df_res[:date], df_res[:q_obs], linewidth = 1.2, color = "k", label = "Observed")
plt[:plot](df_res[:date], df_res[:q_sim], linewidth = 1, color = "r", label = "Simulated")
plt[:legend]()
plt[:title]("KGE = $perf_kge , NSE = $perf_nse")
