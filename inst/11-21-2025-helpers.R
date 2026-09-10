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
  print(tt)
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
  ## tt_end = length(datobj$ylist)
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
