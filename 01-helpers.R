#' Helper to read in CSV file and get a list object containing |ylist| and
#' |biomass_list| (and |datetimes|).
#'
#' @param outputdir Directory that contains the csv file
#' @param csv_filename a csv file.
#'
#' @return A list.
csv_to_datlist <- function(outputdir, csv_filename){
  hourly_gridded = read.csv(file = file.path(outputdir, csv_filename)) %>% as_tibble()
  return(table_to_datlist(hourly_gridded))
}


#' Workhorse for csv_to_datlist.
table_to_datlist <- function(hourly_gridded){
  ylist = hourly_gridded %>% group_by(date) %>% group_split() %>%
    lapply(function(df){
      df %>% select(fsc_small_coord, chl_small_coord, pe_coord) %>% as.matrix()
    })

  biomass_list = hourly_gridded %>% group_by(date) %>% group_split() %>%
    lapply(function(df){
      df %>% pull(Qc)
    })
  datetimes = hourly_gridded$date %>% unique() %>% as_datetime()
  list(ylist = ylist, biomass_list = biomass_list, datetimes = datetimes)

}



#' (Not needed now, since csv_to_datlist()) Gets a |ylist| object from a long
#' matrix.
#'
#' @param gridded_data A long matrix containing columns: date, fsc_small, chl_small_coord, pe_coord and Qc.
#'
#' @return List of 3-column matrices
get_ylist <- function(gridded_data){
  gridded_data %>% group_by(date) %>% group_split() %>%
    lapply(function(df){
      df %>% select(fsc_small_coord, chl_small_coord, pe_coord) %>% as.matrix()
    })
}

#' Gets a |countslist| object from a long matrix.
#'
#' @param gridded_data A long matrix containing columns: date, fsc_small, chl_small_coord, and pe_coord, and Qc.
#'
#' @return List of 3-column matrices
get_biomass_list <- function(gridded_data){
  gridded_data %>% group_by(date) %>% group_split() %>%
    lapply(function(df){
      df %>% select(fsc_small_coord, chl_small_coord, pe_coord) %>% as.matrix()
    })
}





plot_1d_temp <- function (ylist, countslist, times, x = NULL, alpha = 0.1,
                          bin = FALSE, plot_band = TRUE){
    dimdat = ncol(ylist[[1]])
    assertthat::assert_that(dimdat == 1)
    ymat <- lapply(1:length(ylist), FUN = function(tt) {
        data.frame(time = times[tt], Y = ylist[[tt]], counts = countslist[[tt]])
    }) %>% bind_rows() %>% as_tibble() %>%
      mutate(time = lubridate::as_datetime(time))
    colnames(ymat) = c("time", "Y", "counts")
    gg = ymat %>% ggplot() + geom_raster(aes(x = time, y = Y,
                                             fill = counts)) + theme_bw() + ylab("Data") + xlab("Time") +
      scale_fill_gradientn(colours = c("white", "black"))+
    scale_x_datetime(
        date_breaks = "1 day", # Set major breaks every 1 day
    ) +
      theme(
          axis.text.x = element_text(
              angle = 45,        # Rotate labels by 45 degrees
              vjust = 1,         # Adjust vertical justification
              hjust = 1          # Adjust horizontal justification
          )
      )

    return(gg)
}


plot_3d_temp <- function(tt, ylist, biomass_list, dates){

  ## TODO: Set limits to the result of plot_2d() so that the plots all occupy
  ## the same frame.

  dimslist = list(c(1:2), c(2:3), c(3,1))
  ## for(onedate in datetimes){
  ##   tt = which(datetimes == onedate)
    plotlist = lapply(1:3, function(ll){
    capture.output({
      tempdat = flowmix::collapse_3d_to_2d(ylist[[tt]], biomass_list[[tt]], dims = dimslist[[ll]])
    })
      gg1 = flowtrend::plot_2d(ylist      = list(tempdat[,c(1,2)]),
                               countslist = list(tempdat[,3, drop=TRUE]), tt = 1,
                               raster_colours = c("white", "black", "yellow", "red"))
        ## if(ll==1){ gg1 = gg1 + ggtitle(paste0("tt=",tt)) }
        ## if(ll>1){ gg1 = gg1 + ggtitle("") }
        gg1 = gg1 + ggtitle("")
      return(gg1)
    })
    cowplot::plot_grid(plotlist = plotlist, ncol = 3, labels = NULL) %>%
      cowplot::ggdraw() +
      cowplot::draw_label(paste0("t=", tt, ",   ", dates[tt]),
                          x = 0.5, # Center the text horizontally
                          y = .97, # Position the text near the top
                          size = 14)+
      theme(plot.margin = unit(c(.8, 0.5, 0.5, 0.5), "cm"))
}



my_plotter <- function(ylist, countslist, dates, plot_title){
  gg1 = plot_1d_temp(ylist=ylist,
                     countslist = countslist,
                     time = dates) +
    scale_fill_gradientn(colours = c("white", "black", "yellow", "red"))
  gg2 = plot_1d_temp(ylist=ylist,
                     ## countslist = countslist,
                     countslist = countslist %>% sapply(function(a)a/sum(a)),
                     time = dates)  +
    scale_fill_gradientn(colours = c("white", "black", "yellow", "red"))
  gg12 = cowplot::plot_grid(plotlist = list(gg1, gg2), ncol = 1, labels = NULL)   %>%
    cowplot::ggdraw() +
    cowplot::draw_label(plot_title,
                        fontface = 'bold',
                        x = 0.5, # Center the text horizontally
                        y = 1, # Position the text near the top
                        size = 14)+
    theme(plot.margin = unit(c(.6, 0.5, 0.5, 0.5), "cm"))
    }



my_marginal_plotter <- function(ylist, biomass_list, dates = NULL, normalize_by_total_biomass = FALSE){

  plotlist = lapply(1:3, function(idim){


    capture.output({
      datobj_1d = flowmix::collapse_3d_to_1d(ylist = ylist, countslist = biomass_list, idim = idim)
    })

    ## Tiny 1-line helper: snaps whatever data range ggplot sees to the nearest days
    snap_days <- function(x) seq(floor_date(min(x), "day"), ceiling_date(max(x), "day"), by = "6 hours")
    snap_minor <- function(x) seq(floor_date(min(x), "day"), ceiling_date(max(x), "day"), by = "1 day")

    if(!normalize_by_total_biomass){
      countslist = datobj_1d$countslist
    }
    if(normalize_by_total_biomass){
      countslist = datobj_1d$countslist %>% sapply(function(a)a/sum(a))
    }
    flowtrend::plot_1d(ylist = datobj_1d$ylist,
                       countslist = countslist,  bin = TRUE,
                       x = dates) +
      ## scale_x_datetime(
      ##     date_breaks = "6 hours",
      ##     date_labels = "%b %d\n%H:%M" # Formats as 'Month Day' on line 1, 'Hour:Min' on line 2
      ## ) +
      ## scale_x_datetime(
      ##     date_breaks = "12 hours",        # Labels and major gridlines every 6 hours
      ##     date_minor_breaks = "1 day",    # Extra gridlines every day
      ##     date_labels = "%b %d, %H:%M"    # Label format
      ## )+
      scale_x_datetime(
          ## breaks = scales::breaks_width("6 hours", offset = "0 hours"),
          ## minor_breaks = scales::breaks_width("1 day"),
          breaks = snap_days,            # Dynamically creates fixed 12am, 6am, 12pm, 6pm lines
          minor_breaks = snap_minor,     # Dynamically creates midnight lines
          date_labels = "%b %d, %I %p")+
      theme(
          ## Rotate text 45 degrees and align the end of the text to the tick mark
          axis.text.x = element_text(angle = 45, vjust = 1, hjust = 1)
      ) +
      scale_fill_gradientn(colours = c("white", "black", "yellow", "red")) +
      ggtitle(cruisename) +
      ylab(c("fsc (forward scatter)", "chl", "pe")[idim])
  })
  cowplot::plot_grid(plotlist = plotlist, ncol = 1)
}



#' Simple helper function to remove bin
#'
#' @param dimname must be one of c("fsc_small", "chl_small", "pe")
#' @param min_or_max must be one of c("min", "max")
#' @param slack if zero, only remove edge bin; if 1, remove two edge bins.
my_edge_bin_remove <- function(ylist, biomass_list, dimname, min_or_max, slack = 0){

  ## Basic check
  stopifnot(dimname %in% c("fsc_small", "chl_small", "pe"))
  stopifnot(min_or_max %in% c("min", "max"))
  dimname = paste0(dimname, "_coord")

  newer_biomass_list = biomass_list
  newer_ylist = ylist
  discarded_biomass_list = list()
  discarded_ylist = list()

  ## Decide on which bin to remove
  if(min_or_max == "min"){
    bin_to_remove = ylist %>% sapply(function(one_y) min(one_y[,dimname])) %>% median()
    bin_to_remove = bin_to_remove + slack
  }
  if(min_or_max == "max"){
    bin_to_remove = ylist %>% sapply(function(one_y) max(one_y[,dimname])) %>% median()
    bin_to_remove = bin_to_remove - slack
  }

  ## Remove that bin
  TT = length(ylist)
  for(tt in 1:TT){
    one_count = biomass_list[[tt]]
    one_y = ylist[[tt]]
    if(min_or_max == "min"){
      irow_to_remove = which(one_y[,dimname] <= bin_to_remove)
    }
    if(min_or_max == "max"){
      irow_to_remove = which(one_y[,dimname] >= bin_to_remove)
    }
    if(length(irow_to_remove) > 0){
      newer_ylist[[tt]] = one_y[-irow_to_remove,]
      newer_biomass_list[[tt]] = one_count[-irow_to_remove]
      discarded_ylist[[tt]] = one_y[irow_to_remove,]
      discarded_biomass_list[[tt]] = one_count[irow_to_remove]
    } else {
      discarded_ylist[[tt]] = one_y[c(),]
      discarded_biomass_list[[tt]] = one_count[c()]
    }
  }

  return(list(

      ## Cleaned ylist
      ylist = newer_ylist,
      biomass_list = newer_biomass_list,

      ## Censored stuff
      ylist_cens = discarded_ylist,
      biomass_list_cens = discarded_biomass_list
))
}



#' Plot particle-level 3d cytogram at time tt. Shows only a fraction of the data.
#' @param cruisename Cruise name (string).
#' @param tt Time point
#' @param show_censored Show censoring points using different colors (defaults to TRUE)
#' @param frac Fraction of the data to plot.
plotly_particle <- function(cruisename, tt, outputdir, raw_data_dir, show_censored = TRUE, frac = 0.1){
  ## Read particle-level data.
  vct_dir <- str_glue("{raw_data_dir}/{cruisename}/{cruisename}_vct_slim")
  vct_files <- list.files(vct_dir, "\\.parquet$", full.names = TRUE)
  list_of_df = lapply(1:length(vct_files), function(ifile){ read_parquet(vct_files[ifile]) })
  vct <- bind_rows(list_of_df) # FIXME: this crashes
  invisible(gc())

  # TODO: one fix could be to only bind rows corresponding to hour tt
  # TODO: for now, just skip this step

  ## Read in grid bins
  grid_bin_long_table = read.csv(file = file.path(outputdir, grid_filename))
  grid_bins <- reconstruct_grid_bins_from_table(grid_bin_long_table)

  ## Do the actual gridding now
  vct["fsc_small_coord"] <- as.integer(cut(vct[["fsc_small"]],
                                           grid_bins[["fsc_small"]],
                                           labels = FALSE,
                                           right = FALSE))
  vct["pe_coord"] <- as.integer(cut(vct[["pe"]],
                                    grid_bins[["pe"]],
                                    labels = FALSE,
                                    right = FALSE))
  vct["chl_small_coord"] <- as.integer(cut(vct[["chl_small"]],
                                           grid_bins[["chl_small"]],
                                           labels = FALSE,
                                           right = FALSE))

  ## Remove beads
  vct = vct %>% filter(pop != "beads")

  ## Aggregate to hourly level
  hourly_gridded <- vct %>%
    group_by(date=floor_date(date, "1 hours"), across(ends_with("_coord")))

  ## cruisename = "SCOPE_16"
  ## cruisename = "KM1906"
  ## cruisename = "MGL1704"
  ## csv_filename = paste0(cruisename, "-gridded-before-cleaning-new.csv")
  ## hourly_gridded = read.csv(file = file.path(outputdir, csv_filename)) %>% as_tibble()

  a = hourly_gridded %>% group_by(date) %>% group_split() %>% .[[tt]]

  ## 3. Generate the 3D plot
  a_small = a %>% sample_frac(frac)

  if(show_censored){
  max_fsc = a_small %>% summarize(max(fsc_small_coord)) %>% unlist()
  max_chl = a_small %>% summarize(max(chl_small_coord)) %>% unlist()
  max_pe  = a_small %>% summarize(max(pe_coord)) %>% unlist()

  min_fsc = a_small %>% summarize(min(fsc_small_coord)) %>% unlist()
  min_chl = a_small %>% summarize(min(chl_small_coord)) %>% unlist()
  min_pe  = a_small %>% summarize(min(pe_coord)) %>% unlist()

  a_small = a_small %>%
    mutate(color = ifelse(pe_coord==max_pe |
                          pe_coord == min_pe |
                          chl_small_coord == max_chl |
                          chl_small_coord == min_chl |
                          fsc_small_coord == max_fsc |
                          fsc_small_coord == min_fsc, "red", "blue"))
  } else {
    a_small = a_small %>% mutate(color = "blue")
  }

  library(plotly)
  myplot = plot_ly(
      data = a_small,
      x = ~fsc_small,
      y = ~chl_small,
      z = ~pe,
      color = ~color,
      colors = c("red" = "red", "blue" = "blue"),
      size = ~Qc^(1/3),
      type = "scatter3d",
      mode = "markers",
      marker = list(
          sizeref = 5,
          sizemode = "diameter",
          opacity = 0.8
      )
  ) %>%
    layout(
        scene = list(
            xaxis = list(
                type = "log",
                title = "log(fsc_small)"
            ),
            yaxis = list(
                type = "log",
                title = "log(chl_small)"
            ),
            zaxis = list(
                type = "log",
                title = "log(pe)"
            )
        ))
  return(myplot)
}

#' @param y Position of the text near the top.
add_title <- function(myplot, mytitle, y = .97){
  myplot %>%
    cowplot::ggdraw() +
    theme(plot.background = element_rect(color = "grey", size = 1)) +
    cowplot::draw_label(mytitle,
                        x = 0.5, # Center the text horizontally
                        y = y, # Position the text near the top
                        size = 14)+
    theme(plot.margin = unit(c(.8, 0.5, 0.5, 0.5), "cm"))
}





#' Takes binned ylist and biomass_list and dates, and combines it into a long
#' table with columns (date, fsc_small_coord, chl_small_coord, pe_coord, Qc).
#' @param ylist binned
#' @param biomass_list binned
recombine_to_csv <- function(ylist, biomass_list, dates){
  dates_list <- dates %>% as.list()
  recombined_list <- purrr::pmap(list(dates_list, ylist, biomass_list), function(date_str, coords_matrix, qc_vector) {
    coords_tibble <- as_tibble(coords_matrix, .name_repair = "unique")
    colnames(coords_tibble) <- c("fsc_small_coord", "chl_small_coord", "pe_coord") # Rename columns
    coords_tibble %>%
      mutate(date = date_str, Qc = qc_vector)
  })
  hourly_gridded_reconstructed <- bind_rows(recombined_list) %>%
    select(date, fsc_small_coord, chl_small_coord, pe_coord, Qc)
  return(hourly_gridded_reconstructed)
}



#' Combine back to a censored bin table.
recombine_censored_data <- function(all_ylists, all_biomass_lists){

  ## all_ylists = list(ylist_cens_after_chl, ylist_cens_after_chl_and_fsc)
  ## all_biomass_lists = list(biomass_list_cens_after_chl, biomass_list_cens_after_chl_and_fsc)

  ## Combine all the censored data (ylists and biomass lists separately)
  ylist_cens <- do.call(Map, c(f = rbind, all_ylists))
  biomass_list_cens <- do.call(Map, c(f = c, all_biomass_lists))

  ## Visualize it
  if(FALSE){
    collapse_3d_to_2d(ylist_cens[[1]], biomass_list_cens[[1]], dims = c(1,2)) %>%
      ggplot() +
      geom_raster(aes(x=fsc_small_coord, y=chl_small_coord, fill = counts))
  }

  ##
  hourly_gridded_censored_reconstructed =
    recombine_to_csv(ylist_cens, biomass_list_cens, dates)
  return(hourly_gridded_censored_reconstructed)

}


#' Take ylist and biomass_list, and "coarsen" in chl and pe (but not fsc_small)
#' only, so that bins 1:2 become 1, bins 3:4 becomes 2, and so forth.
#'
#' @param ylist binned data.
#' @param biomass_list binned biomass.
#'
#' @return List of new ylist and biomass_list.
coarsen_in_chl_and_pe <- function(ylist, biomass_list, return_combined = FALSE){
  y_b_list = lapply(1:length(ylist), function(tt){
    y_b_mat <-
      ylist[[tt]] %>%
      as.data.frame() %>%
      mutate(value_to_sum = biomass_list[[tt]]) %>%
      mutate(across(c(chl_small_coord, pe_coord), ~ ceiling(.x / 2))) %>%
      group_by(fsc_small_coord, chl_small_coord, pe_coord) %>%
      summarise(biomass = sum(value_to_sum, na.rm = TRUE), .groups = "drop")
    return(y_b_mat)
  })
  if(return_combined) return(y_b_list)

  # Create list containing coarsened binned data ('fsc_small_coord',
  #   'chl_small_coord', 'pe_coord') and biomass ('biomass').
  biomass_list1 <- y_b_list %>%
    lapply(function(onemat)onemat[,"biomass", drop=TRUE])
  ylist1 <- y_b_list %>%
    lapply(function(onemat)
      onemat[,c("fsc_small_coord", "chl_small_coord", "pe_coord")] %>% as.matrix())

  return(list(ylist = ylist1, biomass_list = biomass_list1))

  ## ## Plot
  ## y_b_list_2d <- y_b_list %>% lapply(function(onemat){
  ##   onemat %>% group_by(fsc_small_coord, chl_small_coord) %>%
  ##     summarize(biomass = sum(biomass))
  ## })
  ## return(y_b_list_2d)
}


make_cens_indicator <- function(ylist, cens_lim_l_vec, cens_lim_u_vec){

  ## We'll be creating these
  cens_ind_left = list()
  cens_ind_right = list()

  TT = length(ylist)
  dimdat = ncol(ylist[[1]])

  ## Manually mark all the censored points (bins)
  for(tt in 1:TT){
      cens_ind_left[[tt]] = matrix(NA,nrow(ylist[[tt]]), ncol(ylist[[tt]]))
      cens_ind_right[[tt]] = matrix(NA,nrow(ylist[[tt]]), ncol(ylist[[tt]]))
      for(coord in 1:dimdat){
        cens_ind_left[[tt]][,coord] = ifelse(ylist[[tt]][,coord] <= cens_lim_l_vec[coord],1,NA)
        cens_ind_right[[tt]][,coord] = ifelse(ylist[[tt]][,coord] >= cens_lim_u_vec[coord],1,NA)
      }
    }

  return(list(censor_indicator_left = cens_ind_left,
              censor_indicator_right = cens_ind_right))
}



#' Reconstruct Grid Bins from a Long Table
#'
#' Reconstructs the original list of multi-dimensional grid bin fenceposts (boundaries)
#' from a flattened, long-format tibble/data frame.
#'
#' @param grid_bin_long_table A data frame or tibble containing the flattened grid bins.
#'   Must include the columns:
#'   \itemize{
#'     \item \code{dimname}: Character. The name of the dimension (e.g., "fsc_small").
#'     \item \code{coord}: Integer. The sequential bin index.
#'     \item \code{left_fencepost}: Numeric. The left boundary of the bin.
#'     \item \code{right_fencepost}: Numeric. The right boundary of the bin.
#'   }
#'
#' @return A named \code{list} of numeric vectors, where each element represents the
#'   sequential fenceposts (length $N+1$ for $N$ bins) for that specific dimension,
#'   ordered exactly as they first appear in the input table.
#'
#' @import dplyr
#' @import purrr
#' @export
#'
#' @examples
#' \dontrun{
#' # Assuming grid_bin_long_table exists in your environment:
#' original_bins <- reconstruct_grid_bins_from_table(grid_bin_long_table)
#' }
reconstruct_grid_bins_from_table <- function(grid_bin_long_table){

  ## Setup
  prepared_table <- grid_bin_long_table %>%
    mutate(dimname = factor(dimname, levels = unique(grid_bin_long_table$dimname))) %>%
    arrange(dimname, coord)

  ## Extract the ordered names
  group_names <- levels(prepared_table$dimname)

  ## Reconstruct the list; this preserves the original dimension and ordering
  ## (and accounts for trailing `NA` values introduced during table creation.)
  reconstructed_grid_bins <- prepared_table %>%
    group_by(dimname) %>%
    # Take all the left fenceposts, and append the second-to-last right_fencepost (to bypass the NA)
    group_map(~ c(.x$left_fencepost, .x$right_fencepost[nrow(.x) - 1])) %>%
    set_names(group_names)

  return(reconstructed_grid_bins)
}
