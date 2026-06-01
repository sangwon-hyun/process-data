#' Helper to read in CSV file and get a list object containing |ylist| and
#' |biomass_list|.
#'
#' @param outputdir Directory that contains the csv file
#' @param csv_filename a csv file.
#'
#' @return A list.
csv_to_datlist <- function(outputdir, csv_filename){
  hourly_gridded = read.csv(file = file.path(outputdir, csv_filename)) %>% as_tibble()
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


plot_3d_temp <- function(tt, ylist, biomasslist){
dimslist = list(c(1:2), c(2:3), c(3,1))
## for(onedate in datetimes){
##   tt = which(datetimes == onedate)
  plotlist = lapply(1:3, function(ll){
    tempdat = flowmix::collapse_3d_to_2d(ylist[[tt]], biomass_list[[tt]], dims = dimslist[[ll]])
    gg1 = flowtrend::plot_2d(ylist=list(tempdat[,c(1,2)]), countslist = list(tempdat[,3, drop=TRUE]), tt = 1,
                             raster_colours = c("white", "black", "yellow", "red"))
      if(ll==1){ gg1 = gg1 + ggtitle(paste0("tt=",tt)) }
      if(ll>1){ gg1 = gg1 + ggtitle("") }
    return(gg1)
  })
  cowplot::plot_grid(plotlist = plotlist, ncol = 3, labels = NULL)
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



my_marginal_plotter <- function(ylist, biomass_list, dates = NULL){

  plotlist = lapply(1:3, function(idim){
    datobj_1d = flowmix::collapse_3d_to_1d(ylist = ylist, countslist = biomass_list, idim = idim)
    flowtrend::plot_1d(ylist = datobj_1d$ylist,
                       countslist = datobj_1d$countslist,  bin = TRUE,
                       x = dates) +
      scale_fill_gradientn(colours = c("white", "black", "yellow", "red")) +
      ggtitle(cruisename) +
      ylab(c("fsc (forward scatter)", "chl", "pe")[idim])
  })
  cowplot::plot_grid(plotlist = plotlist, ncol = 1) %>% print()
}



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
    }
  }

  return(list(ylist = newer_ylist,
              biomass_list = newer_biomass_list))
}
