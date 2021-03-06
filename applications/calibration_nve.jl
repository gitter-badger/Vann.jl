################################################################################

using Vann
using RCall
using DataFrames
using JLD


################################################################################

if is_linux()
  path_inputs = "//hdata/fou/jmg/FloodForecasting/Data";
  path_save = "//hdata/fou/jmg/FloodForecasting/Results";
end

if is_windows()
  path_inputs = "C:/Work/VannData/Input";
  path_save = "C:/Work/VannData";
end

epot_choice = epot_monthly;
snow_choice = TinBasic;
hydro_choice = Gr4j;

calib_start = DateTime(2000,09,01);
calib_stop = DateTime(2014,12,31);

valid_start = DateTime(1985,09,01);
valid_stop = DateTime(2000,08,31);


################################################################################

# Folder for saving results

time_now = Dates.format(now(), "yyyymmddHHMM");

path_save = path_save * "/" * time_now * "_Results";

mkpath(path_save * "/calib_txt")
mkpath(path_save * "/calib_png")
mkpath(path_save * "/valid_txt")
mkpath(path_save * "/valid_png")
mkpath(path_save * "/param_snow")
mkpath(path_save * "/param_hydro")
mkpath(path_save * "/model_data")


################################################################################

# Function for plotting results

function plot_results(df_res, period, file_save)

  days_warmup = 3*365;

  df_res = df_res[days_warmup:end, :];

  R"""
  library(zoo, lib.loc = 'C:/Users/jmg/Documents/R/win-library/3.2')
  library(hydroGOF, lib.loc = 'C:/Users/jmg/Documents/R/win-library/3.2')
  library(labeling, lib.loc = 'C:/Users/jmg/Documents/R/win-library/3.2')
  library(ggplot2, lib.loc = 'C:/Users/jmg/Documents/R/win-library/3.2')

  df <- $df_res
  df$date <- as.Date(df$date)
  df$q_obs[df$q_obs == -999] <- NA

  kge <- round(KGE(df$q_sim, df$q_obs), digits = 2)
  nse <- round(NSE(df$q_sim, df$q_obs), digits = 2)

  plot_title <- paste('KGE = ', kge, ', NSE = ', nse, sep = '')
  path_save <- $path_save
  file_save <- $file_save
  period <- $period

  p <- ggplot(df, aes(date))
  p <- p + geom_line(aes(y = q_sim),colour = 'red', size = 0.5)
  p <- p + geom_line(aes(y = q_obs),colour = 'blue', size = 0.5)
  p <- p + theme_bw()
  p <- p + labs(title = plot_title)
  p <- p + labs(y = 'Date')
  p <- p + labs(y = 'Discharge (mm/day)')
  ggsave(file = paste(path_save,'/',period,'_png/',file_save,'_station.png', sep = ''), width = 30, height = 18, units = 'cm', dpi = 600)
  """

end

################################################################################

# Loop over all watersheds

dir_all = readdir(path_inputs);

for dir_cur in dir_all

  ########################### Calibration period ###############################

  # Load data

  date, tair, prec, q_obs, frac = load_data("$path_inputs/$dir_cur");

  # Crop data

  date, tair, prec, q_obs = crop_data(date, tair, prec, q_obs, calib_start, calib_stop);

  # Compute potential evapotranspiration

  epot = eval(Expr(:call, epot_choice, date));

  # Initilize model

  st_snow = eval(Expr(:call, snow_choice, frac));
  st_hydro = eval(Expr(:call, hydro_choice, frac));

  # Run calibration

  param_snow, param_hydro = run_model_calib(st_snow, st_hydro, date, tair, prec, epot, q_obs);

  println(param_snow)
  println(param_hydro)

  # Reinitilize model

  st_snow = eval(Expr(:call, snow_choice, param_snow, frac));
  st_hydro = eval(Expr(:call, hydro_choice, param_hydro, frac));

  # Run model with best parameter set

  q_sim = run_model(st_snow, st_hydro, date, tair, prec, epot);

  # Store results in data frame

  q_obs = round(q_obs, 2);
  q_sim = round(q_sim, 2);

  df_res = DataFrame(date = Dates.format(date,"yyyy-mm-dd"), q_sim = q_sim, q_obs = q_obs);

  # Save results to txt file

  file_save = dir_cur[1:end-5]

  writetable(string(path_save, "/calib_txt/", file_save, "_station.txt"), df_res, quotemark = '"', separator = '\t')

  # Plot results using rcode

  period = "calib";

  plot_results(df_res, period, file_save)

  ########################### Validation period ################################

  # Load data

  date, tair, prec, q_obs, frac = load_data("$path_inputs/$dir_cur");

  # Crop data

  date, tair, prec, q_obs = crop_data(date, tair, prec, q_obs, valid_start, valid_stop);

  # Compute potential evapotranspiration

  epot = eval(Expr(:call, epot_choice, date));

  # Reinitilize model

  st_snow = eval(Expr(:call, snow_choice, param_snow, frac));
  st_hydro = eval(Expr(:call, hydro_choice, param_hydro, frac));

  # Run model with best parameter set

  q_sim = run_model(st_snow, st_hydro, date, tair, prec, epot);

  # Store results in data frame

  q_obs = round(q_obs, 2);
  q_sim = round(q_sim, 2);

  df_res = DataFrame(date = Dates.format(date,"yyyy-mm-dd"), q_sim = q_sim, q_obs = q_obs);

  # Save results to txt file

  file_save = dir_cur[1:end-5];

  writetable(string(path_save, "/valid_txt/", file_save, "_station.txt"), df_res, quotemark = '"', separator = '\t');

  # Plot results using rcode

  period = "valid";

  plot_results(df_res, period, file_save)

  # Save parameter values

  writedlm(path_save * "/param_snow/" * file_save * "_param_snow.txt", param_snow);
  writedlm(path_save * "/param_hydro/" * file_save * "_param_hydro.txt", param_hydro);

  st_snow = eval(Expr(:call, snow_choice, param_snow, frac));
  st_hydro = eval(Expr(:call, hydro_choice, param_hydro, frac));

  jldopen(path_save * "/model_data/" * file_save * "_modeldata.jld", "w") do file
    addrequire(file, Vann)
    write(file, "st_snow", st_snow)
    write(file, "st_hydro", st_hydro)
  end

end
