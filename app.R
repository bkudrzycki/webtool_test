# Package names
packages <- c("devtools", "DT", "here", "leaflet", "openxlsx", "shiny", "tidyverse", "usethis", "shinythemes", "viridis", "tigris", "rgdal", "leaflet.extras", "shinyWidgets")

# Install packages not yet installed
installed_packages <- packages %in% rownames(installed.packages())
if (any(installed_packages == FALSE)) {
  install.packages(packages[!installed_packages])
}

# Packages loading
invisible(lapply(packages, library, character.only = TRUE))
## ---------------------------------------

devtools::load_all(here("lamadex"))

# load map, shapefile name "countries", country names saved as NAME

load(here("data", "shapeFile.RData"))

# globals: load list of countries and raw data, define geometric mean function
source(here("lamadex", "R", "source", "countryList.R"))
source(here("lamadex", "R", "source", "data_loader.R"))
gm_mean = function(x, na.rm = FALSE) {
  exp(sum(log(x[x > 0]), na.rm=na.rm) / length(x[!is.na(x)]))
}

# background color
css <- HTML(" body {
    background-color: #4e5d6c;
}")

# Define UI
ui <- fluidPage(
  tags$head(
    tags$style(HTML(".leaflet-container { background: #4e5d6c; }"))
  ),
  navbarPage("YLILI", theme = shinytheme("superhero"),
             tags$head(
               tags$style(css)),
             tabPanel("Youth Labor Market Index for Low-Income Countries", fluid = TRUE),
             # Sidebar layout with a input and output definitions
             sidebarLayout(
               sidebarPanel(
                 # App title ----
                 titlePanel("Data Explorer"),
                 fluidRow(
                   column(8,
                          checkboxInput("impute", "Impute missing values", value = TRUE),
                          sliderInput("lastyear", "Last year:",
                                      min = 2000, max = 2017,
                                      value = 2010, sep = "", ticks = FALSE),
                          selectInput("dim_agg", "Dimension aggregation", c("Arithmetic", "Geometric")),
                          selectInput("score_agg", "Index aggregation", c("Arithmetic", "Geometric")),
                          selectInput("gender", "Gender", c("Total", "Male", "Female")),
                          hr())
                 ),
                 fluidRow(
                   column(4,
                          submitButton("Update")
                   ),
                   column(4,
                          downloadButton("dl", "Download .Excel")
                   )
                 ),
                 fluidRow(
                   column(8,
                          hr(),
                          selectizeInput("select", "Show on map:",
                                         c("YLILI Score" = "YLILI score",
                                           "Transition" = "Transition",
                                           "Working conditions" = "Working conditions",
                                           "Education" = "Education",
                                           "NEET score" = "NEET score",
                                           "Working conditions ratio" =  "Working conditions ratio",
                                           "Mismatch score" = "Mismatch score",
                                           "Working poverty score" = "Working poverty score",
                                           "Under- employment score" = "Under- employment score",
                                           "Informal work score" = "Informal work score",
                                           "Elementary occupation score" = "Elementary occupation score",
                                           "Secondary schooling rate" = "Secondary schooling rate",
                                           "Literacy rate" = "Literacy rate",
                                           "Harmonized tests score" = "Harmonized tests score"),
                                         multiple = FALSE)
                   )
                 ),
                 width = 2,
               ),
               mainPanel(
                 tabsetPanel(
                   id = 'dataset',
                   tabPanel("Map",
                            style = "height:92vh;",
                            leafletOutput("map", width = "120%", height = "93%")),
                   tabPanel("Data", DT::dataTableOutput("ranks"))
                 )
               )
             )
  )
)


# Define server logic
server <- function(input, output) {
  
  # generate index according to user-specified preferences
  reactiveIndex <- reactive(rank_generator(dfList, country_lists[[3]], bygender = input$gender, lastyear = input$lastyear, impute = input$impute) %>% 
                              rowwise() %>%
                              mutate(transdim = ifelse(input$dim_agg == "Arithmetic", transition_mean, transition_geom),
                                     wcdim = ifelse(input$dim_agg == "Arithmetic", working_conditions_mean, working_conditions_geom),
                                     educdim = ifelse(input$dim_agg == "Arithmetic", education_mean, education_geom),
                                     arith_score = mean(c(transdim,wcdim,educdim)),
                                     geom_score = gm_mean(c(transdim,wcdim,educdim)), na.rm = FALSE) %>%  # don't generate if missing dims
                              mutate(score = ifelse(input$score_agg == "Arithmetic", arith_score, geom_score)) %>% 
                              select(
                                Country = country,
                                "YLILI score" = score,
                                "Transition" = transdim,
                                "Working conditions" = wcdim,
                                "Education" = educdim,
                                "NEET score" = neet,
                                "Working conditions ratio" = relative_wc,
                                "Mismatch score" = mismatch,
                                "Working poverty score" = workingpov,
                                "Under- employment score" = underemp,
                                "Informal work score" = informal,
                                "Elementary occupation score" = elementary,
                                "Secondary schooling rate" = nosecondary,
                                "Literacy rate" = literacy,
                                "Harmonized tests score" = test_scores
                              )
  )
  
  
  observe({
    
    indicator <- input$select
    chosen_indicator <- reactive(reactiveIndex()[, c("Country", as.character(input$select)), drop=FALSE])
    
    scores<-reactive(left_join(data.frame(Country = countries$NAME%>%as.character()), chosen_indicator()))
    
    pal <- reactive(colorNumeric(c("#FFFFFFFF", viridis(256)), domain = c(min(scores()[2], na.rm = T), max(scores()[2], na.rm = T)), na.color = "white"))
    
    # 
    countries2 <- reactive(merge(countries,
                                 scores(),
                                 by.x = "NAME",
                                 by.y = "Country",
                                 sort = FALSE))
    
    country_popup <- paste0("<strong>Country: </strong>",
                            countries2()$NAME,
                            "<br><strong>",
                            input$gender, " ", as.character(indicator),":",
                            " </strong>",
                            round(countries2()[[indicator]],2),
                            hr())
    
    output$map <- renderLeaflet({
      
      # Use leaflet() here, and only include aspects of the map that
      # won't need to change dynamically (at least, not unless the
      # entire map is being torn down and recreated).
      
      leaflet(countries2()) %>% 
        addPolygons(data = countries2(),
                    fillColor = ~pal()(countries2()[[indicator]]),
                    layerId = ~NAME, weight = 1, smoothFactor = 0.5,
                    opacity = .8, fillOpacity = .8,  color = "#BDBDC3",
                    highlightOptions = highlightOptions(color = "black", weight = 2, opacity = .8),
                    popup = country_popup) %>% 
        setView(10, 20, zoom = 3) %>% 
        addLegend(position = "bottomright",
                  pal = pal(),
                  value = c(min(scores()[2], na.rm = T), max(scores()[2], na.rm = T)))
    })
  })
  
  
  output$ranks <- DT::renderDataTable({
    rank <- reactiveIndex() %>% 
      mutate_if(is.numeric, round, 3) %>% 
      arrange(desc(`YLILI score`))
    nums <- rank %>% select_if(is.numeric)
    brks <- quantile(nums, probs = seq(.05, .95, .05), na.rm = TRUE)
    clrs_index <- round(seq(255, 40, length.out = length(brks) + 1), 0) %>%
      {paste0("rgb(255,", ., ",", ., ")")}
    clrs_dims <- round(seq(150, 80, length.out = length(brks) + 1), 0) %>%
      {paste0("rgb(", ., ",", 75+.,",", ., ")")}
    clrs <- round(seq(200, 120, length.out = length(brks) + 1), 0) %>%
      {paste0("rgb(", ., ",", ., ",255)")}
    DT::datatable(rank, options = list(paging = FALSE, searching = FALSE)) %>% 
      formatStyle(names(rank["YLILI score"]), backgroundColor = styleInterval(brks, clrs_index)) %>% 
      formatStyle(names(rank[c("Transition", "Working conditions", "Education")]), backgroundColor = styleInterval(brks, clrs_dims)) %>% 
      formatStyle(names(rank[c(6:ncol(rank))]), backgroundColor = styleInterval(brks, clrs))
  })
  
  data_list <- reactive({
    list(
      total = rank_generator(dfList, country_lists[[3]], bygender = input$gender, lastyear = input$lastyear, impute = input$impute) %>% 
        rowwise() %>%
        mutate(transdim = ifelse(input$dim_agg == "Arithmetic", transition_mean, transition_geom),
               wcdim = ifelse(input$dim_agg == "Arithmetic", working_conditions_mean, working_conditions_geom),
               educdim = ifelse(input$dim_agg == "Arithmetic", education_mean, education_geom)) %>% 
        mutate(arith_score = mean(c(transdim,wcdim,educdim)),
               geom_score = gm_mean(c(transdim,wcdim,educdim)), na.rm = FALSE) %>% 
        mutate(score = ifelse(input$score_agg == "Arithmetic", arith_score, geom_score)) %>% 
        select(
          Country = country,
          "YLILI score" = score,
          "Transition" = transdim,
          "Working conditions" = wcdim,
          "Education" = educdim,
          "NEET score" = neet,
          "Working conditions ratio" = relative_wc,
          "Mismatch score" = mismatch,
          "Working poverty score" = workingpov,
          "Under- employment score" = underemp,
          "Informal work score" = informal,
          "Elementary occupation score" = elementary,
          "Secondary schooling rate" = nosecondary,
          "Literacy rate" = literacy,
          "Harmonized tests score" = test_scores
        ) %>% 
        arrange(desc(`YLILI score`)),
      male = rank_generator(dfList, country_lists[[3]], bygender = "Male", lastyear = input$lastyear, impute = input$impute) %>% 
        rowwise() %>%
        mutate(transdim = ifelse(input$dim_agg == "Arithmetic", transition_mean, transition_geom),
               wcdim = ifelse(input$dim_agg == "Arithmetic", working_conditions_mean, working_conditions_geom),
               educdim = ifelse(input$dim_agg == "Arithmetic", education_mean, education_geom)) %>% 
        mutate(arith_score = mean(c(transdim,wcdim,educdim)),
               geom_score = gm_mean(c(transdim,wcdim,educdim)), na.rm = FALSE) %>% 
        mutate(score = ifelse(input$score_agg == "Arithmetic", arith_score, geom_score)) %>% 
        select(
          Country = country,
          "YLILI score" = score,
          "Transition" = transdim,
          "Working conditions" = wcdim,
          "Education" = educdim,
          "NEET score" = neet,
          "Working conditions ratio" = relative_wc,
          "Mismatch score" = mismatch,
          "Working poverty score" = workingpov,
          "Under- employment score" = underemp,
          "Informal work score" = informal,
          "Elementary occupation score" = elementary,
          "Secondary schooling rate" = nosecondary,
          "Literacy rate" = literacy,
          "Harmonized tests score" = test_scores
        ) %>% 
        arrange(desc(`YLILI score`)),
      female = rank_generator(dfList, country_lists[[3]], bygender = "Female", lastyear = input$lastyear, impute = input$impute) %>% 
        rowwise() %>%
        mutate(transdim = ifelse(input$dim_agg == "Arithmetic", transition_mean, transition_geom),
               wcdim = ifelse(input$dim_agg == "Arithmetic", working_conditions_mean, working_conditions_geom),
               educdim = ifelse(input$dim_agg == "Arithmetic", education_mean, education_geom)) %>% 
        mutate(arith_score = mean(c(transdim,wcdim,educdim)),
               geom_score = gm_mean(c(transdim,wcdim,educdim)), na.rm = FALSE) %>% 
        mutate(score = ifelse(input$score_agg == "Arithmetic", arith_score, geom_score)) %>% 
        select(
          Country = country,
          "YLILI score" = score,
          "Transition" = transdim,
          "Working conditions" = wcdim,
          "Education" = educdim,
          "NEET score" = neet,
          "Working conditions ratio" = relative_wc,
          "Mismatch score" = mismatch,
          "Working poverty score" = workingpov,
          "Under- employment score" = underemp,
          "Informal work score" = informal,
          "Elementary occupation score" = elementary,
          "Secondary schooling rate" = nosecondary,
          "Literacy rate" = literacy,
          "Harmonized tests score" = test_scores
        ) %>% 
        arrange(desc(`YLILI score`))
    )
  })
  
  output$dl <- downloadHandler(
    filename = function() {"ylili.xlsx"},
    content = function(file) {write.xlsx(data_list(), file)}
  )
  
}

app <- shinyApp(ui = ui, server = server)
