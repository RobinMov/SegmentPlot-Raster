library('move')
library('shiny')
library('raster')
library('foreach')
library('sf')
#library('fasterize')
library('rgeos')
library('fields')
library('stars')
library("shinycssloaders")

#setwd("/root/app/")

## adjust placements of grid ant meth
## fix reading in costlines
## maybe rethink panel title...

shinyModuleUserInterface <- function(id, label) {
  ns <- NS(id)
  
  tagList(
    titlePanel("Fast raster map (sf)"),
    fluidRow(
      column(3, sliderInput(inputId = ns("grid"), 
                label = "Choose a raster grid size in m", 
                value = 50000, min = 1000, max = 300000))
      # column(8,radioButtons(inputId = ns("meth"),
      #           label = "Select rasterizing method",
      #           choices = c("st_rasterize of lines (fast and new)" = "sf","fasterize with buffer (slow for dense data)" = "fast", "rasterize as lines (slow for large data)"="rast"),
      #           selected = "sf", inline = TRUE))
    ),
    
    withSpinner(plotOutput(ns("map"),height="85vh"))
  )
}


shinyModule <- function(input, output, session, data) {
  current <- reactiveVal(data)
  
    data.split <- move::split(data)
    
    #remove all move objects with less than 2 positions
    data.split_nozero <- data.split[unlist(lapply(data.split, length) > 1)]
    if (length(data.split_nozero)==0) logger.info("Warning! Error! There are no segments (or at least 2 positions) in your data set. No rasterization of the tracks possible.") # this is very unlikely, therefore not adaption in the below code for it.

    L <- foreach(datai = data.split_nozero) %do% {
      print(namesIndiv(datai))
      Line(coordinates(datai))
    }
    names(L) <- names(data.split_nozero)
    
    Ls <-  Lines(L,"ID"="segm")
    sLs <- SpatialLines(list(Ls),proj4string=CRS("+proj=longlat +ellps=WGS84"))

    sLsT <- spTransform(sLs,CRSobj="+proj=aeqd +lat_0=53 +lon_0=24 +x_0=0 +y_0=0 +ellps=WGS84 +units=m +no_defs")
    
    outputRaster <- reactive({
      raster(ext=extent(sLsT), resolution=input$grid, crs = "+proj=aeqd +lat_0=53 +lon_0=24 +x_0=0 +y_0=0 +ellps=WGS84 +units=m +no_defs", vals=NULL)
    })
    
    out <- reactive({
      # if (input$meth=="sf")
      # {
        logger.info(paste("sf_rasterize() - updated method with better performance."))
        datat <- spTransform(data,CRSobj="+proj=aeqd +lat_0=53 +lon_0=24 +x_0=0 +y_0=0 +ellps=WGS84 +units=m +no_defs")
        sarea <- st_bbox(datat, crs=CRS("+proj=aeqd +lat_0=53 +lon_0=24 +x_0=0 +y_0=0 +ellps=WGS84 +units=m +no_defs"))
        grd <- st_as_stars(sarea,dx=input$grid,dy=input$grid,values=0) #have to transform into aequ, unit= m
        sfrast <- lapply(data.split_nozero, function (x) {
          xt <- spTransform(x,CRSobj="+proj=aeqd +lat_0=53 +lon_0=24 +x_0=0 +y_0=0 +ellps=WGS84 +units=m +no_defs")
          ls <- st_sf(a = 1, st_sfc(st_linestring(coordinates(xt))), crs=CRS("+proj=longlat +datum=WGS84"))
          tmp <- st_rasterize(ls, grd, options="ALL_TOUCHED=TRUE")
          tmp[is.na(tmp)] <- 0
          return(tmp)
          message(paste("Done with ", xt@idData$local_identifier, ".", sep=""))
        })
      sumRas <- sfrast[[1]]
      for (i in seq(along=sfrast)[-1]) sumRas <- sumRas+sfrast[[i]]
      sumRas[sumRas==0] <- NA
      res <- as(sumRas,"Raster")
      # } else if (input$meth=="fast")
      # {
      #   logger.info(paste("fasterize() for fast raster plotting. Calculated buffer polygon of width",input$grid/4,". Buffer slow if dense points."))
      # 
      # sLsT.poly <- gBuffer(sLsT,width=input$grid/4) #this seems to be a bottleneck for dense data
      # sLsT.sf <- st_as_sf(sLsT.poly)
      # res <- fasterize(sLsT.sf,outputRaster(),fun="count")
      # if (length(res)==1 & is.na(values(res)[1]))
      #  {
      #   values(res) <- 1
      #   logger.info("Output is just one raster cell with NA density. Likely not enough data points or too large grid size. Return single cell raster with value 1.")
      #   }
      # } else if (input$meth=="rast")
      # {
      # logger.info("rasterize() for more flexible and correct, but slow raster plotting. No buffer.")
      # res <- rasterize(sLsT,outputRaster(),fun=function(x,...) sum(length(na.omit(x))),update=TRUE,background=NA)
      # res[res==0] <- NA
      # if (length(res)==1 & is.na(values(res)[1]))
      #   {
      #   values(res) <- 1
      #   logger.info("Output is just one raster cell with NA density. Likely not enough data points or too large grid size. Return single cell raster with value 1.")
      #   }
      # } else (logger.info("No valid rasterization method selected"))
      res
    })

  #coastlinesObj <- reactive({
    coastlines <- readOGR(dsn=getAppFilePath("ne-coastlines-10m"),layer="ne_10m_coastline")
    # coastlines <- readOGR(dsn="./ne-coastlines-10m/",layer="ne_10m_coastline")
    ##coastlines <- readOGR(paste0(getAppFilePath("coastlines")),"ne_10m_coastline") #appspec does not show path, necessary?
    #if (raster::area(gEnvelope(migrasterObj())) > input$grid)
   coastlinesC <- crop(coastlines,extent(sLs))
    #else coastlinesC <- coastlines
    coast <- spTransform(coastlinesC,CRSobj="+proj=aeqd +lat_0=53 +lon_0=24 +x_0=0 +y_0=0 +ellps=WGS84 +units=m +no_defs")
  #  coast
  #})

  output$map <- renderPlot({
    plot(out(),colNA=NA,axes=FALSE,asp=1,col=tim.colors(256))
    plot(coast, add = TRUE)
  })
  
  return(reactive({ current() }))
}


