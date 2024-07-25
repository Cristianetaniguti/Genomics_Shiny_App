#' diversity UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
mod_diversity_ui <- function(id){
  ns <- NS(id)
  tagList(
    # Add GWAS content here
    fluidRow(
      column(width = 3,
             box(title="Inputs", width = 12, collapsible = TRUE, collapsed = FALSE, status = "info", solidHeader = TRUE,
                 fileInput(ns("diversity_file"), "Choose Genotypes File", accept = c(".csv",".vcf",".gz")),
                 #fileInput("pop_file", "Choose Passport File"),
                 #textInput("output_name", "Output File Name"),
                 numericInput(ns("diversity_ploidy"), "Species Ploidy", min = 1, value = NULL),
                 selectInput(ns("zero_value"), "What are the Dosage Calls?", choices = c("Reference Allele Counts", "Alternate Allele Counts"), selected = NULL),
                 #numericInput("cores", "Number of CPU Cores", min = 1, max = (future::availableCores() - 1), value = 1),
                 actionButton(ns("diversity_start"), "Run Analysis"),
                 #downloadButton("download_pca", "Download All Files"),
                 #plotOutput("pca_plot"), # Placeholder for plot outputs
                 #checkboxGroupInput("files_to_download", "Select files to download:",
                 #choices = c("PC1vPC2 plot", "PC2vPC3 plot"), selected = c("table1", "table2"))
                 div(style="display:inline-block; float:right",dropdownButton(
                   tags$h3("Diversity Parameters"),
                   #selectInput(inputId = 'xcol', label = 'X Variable', choices = names(iris)),
                   #selectInput(inputId = 'ycol', label = 'Y Variable', choices = names(iris), selected = names(iris)[[2]]),
                   #sliderInput(inputId = 'clusters', label = 'Cluster count', value = 3, min = 1, max = 9),
                   "Add description of each filter",
                   circle = FALSE,
                   status = "warning",
                   icon = icon("info"), width = "300px",
                   tooltip = tooltipOptions(title = "Click to see info!")
                 ))#,
                 #style = "overflow-y: auto; height: 550px"
             ),
             box(title = "Plot Controls", width=12, status = "warning", solidHeader = TRUE, collapsible = TRUE,
                 sliderInput(ns("hist_bins"),"Histogram Bins", min = 1, max = 200, value = c(20), step = 1),
                 div(style="display:inline-block; float:left",dropdownButton(
                   tags$h3("Save Image"),
                   selectInput(inputId = ns('div_figure'), label = 'Figure', choices = c("Dosage Plot",
                                                                                         "AF Histogram",
                                                                                         "MAF Histogram",
                                                                                         "OHet Histogram")),
                   selectInput(inputId = ns('div_image_type'), label = 'File Type', choices = c("jpeg","pdf","tiff","png"), selected = "jpeg"),
                   sliderInput(inputId = ns('div_image_res'), label = 'Resolution', value = 300, min = 50, max = 1000, step=50),
                   sliderInput(inputId = ns('div_image_width'), label = 'Width', value = 8, min = 1, max = 20, step=0.5),
                   sliderInput(inputId = ns('div_image_height'), label = 'Height', value = 5, min = 1, max = 20, step = 0.5),
                   fluidRow(
                     downloadButton(ns("download_div_figure"), "Save Image"),
                     downloadButton(ns("download_div_file"), "Save Files")),
                   circle = FALSE,
                   status = "danger",
                   icon = icon("floppy-disk"), width = "300px",
                   tooltip = tooltipOptions(title = "Click to see inputs!")
                 ))
             )
      ),
      column(width = 6,
             box(
               title = "Plots", status = "info", solidHeader = FALSE, width = 12, height = 550,
               bs4Dash::tabsetPanel(
                 tabPanel("Dosage Plot", plotOutput(ns('dosage_plot')),style = "overflow-y: auto; height: 500px"),
                 tabPanel("AF Plot", plotOutput(ns('af_plot')),style = "overflow-y: auto; height: 500px"),
                 tabPanel("MAF Plot", plotOutput(ns('maf_plot')),style = "overflow-y: auto; height: 500px"),
                 tabPanel("OHet Plot", plotOutput(ns('het_plot')),style = "overflow-y: auto; height: 500px"),
                 tabPanel("Sample Table", DTOutput(ns('sample_table')),style = "overflow-y: auto; height: 470px"),
                 tabPanel("SNP Table", DTOutput(ns('snp_table')),style = "overflow-y: auto; height: 470px")
               )
             )
      ),
      column(width = 3,
             #valueBoxOutput("snps"),
             valueBoxOutput(ns("mean_het_box"), width = NULL),
             valueBoxOutput(ns("mean_maf_box"), width = NULL),
             box(title = "Status", width = 12, collapsible = TRUE, status = "info",
                 progressBar(id = ns("pb_diversity"), value = 0, status = "info", display_pct = TRUE, striped = TRUE, title = " ")
             )
             #valueBoxOutput("mean_pic_box", width = NULL),
             #valueBox(0,"Mean Heterozygosity", icon = icon("dna"), width = NULL, color = "info"),
             #valueBox(0,"Mean Minor-Allele-Frequency", icon = icon("dna"), width = NULL, color = "info"), #https://rstudio.github.io/shinydashboard/structure.html#tabbox
             #valueBox(0,"Mean PIC", icon = icon("dna"), width = NULL, color = "info")
      )
    )
  )
}

#' diversity Server Functions
#'
#' @importFrom tibble rownames_to_column
#' @importFrom graphics axis hist points
#'
#' @noRd
mod_diversity_server <- function(id){
  moduleServer( id, function(input, output, session){
    ns <- session$ns
    #######Genomic Diversity analysis

    #Genomic Diversity output files
    diversity_items <- reactiveValues(
      diversity_df = NULL,
      dosage_df = NULL,
      box_plot = NULL,
      het_df = NULL,
      maf_df = NULL
    )

    #Reactive boxes
    output$mean_het_box <- renderValueBox({
      valueBox(
        value = 0,
        subtitle = "Mean Heterozygosity",
        icon = icon("dna"),
        color = "info"
      )
    })

    output$mean_maf_box <- renderValueBox({
      valueBox(
        value = 0,
        subtitle = "Mean MAF",
        icon = icon("dna"),
        color = "info"
      )
    })

    observeEvent(input$diversity_start, {
      req(input$diversity_file, input$diversity_ploidy, input$zero_value)

      #Input variables (need to add support for VCF file)
      ploidy <- as.numeric(input$diversity_ploidy)
      geno <- input$diversity_file$datapath
      #geno_mat <- read.csv(input$diversity_file$datapath, header = TRUE, check.names = FALSE, row.names = 1)
      #pheno <- read.csv(input$pop_file$datapath, header = TRUE, check.names = FALSE)

      #Status
      updateProgressBar(session = session, id = "pb_diversity", value = 20, title = "Importing VCF")

      #Import genotype information if in VCF format
      vcf <- read.vcfR(geno)

      convert_to_dosage <- function(gt) {
        # Split the genotype string
        alleles <- strsplit(gt, "[|/]")
        # Sum the alleles, treating NA values appropriately
        sapply(alleles, function(x) {
          if (any(is.na(x))) {
            return(NA)
          } else {
            return(sum(as.numeric(x), na.rm = TRUE))
          }
        })
      }

      #Get items in FORMAT column
      info <- vcf@gt[1,"FORMAT"] #Getting the first row FORMAT
      extract_info_ids <- function(info_string) {
        # Split the INFO string by ';'
        info_parts <- strsplit(info_string, ":")[[1]]
        # Extract the part before the '=' in each segment
        info_ids <- gsub("=.*", "", info_parts)
        return(info_ids)
      }

      # Apply the function to the first INFO string
      info_ids <- extract_info_ids(info[1])

      #Status
      updateProgressBar(session = session, id = "pb_diversity", value = 40, title = "Converting to Numeric")

      #Get the genotype values if the updog dosage calls are present
      if ("UD" %in% info_ids) {
        geno_mat <- extract.gt(vcf, element = "UD")
        class(geno_mat) <- "numeric"
        rm(vcf) #Remove vcf
      }else{
        #Extract GT and convert to numeric calls
        geno_mat <- extract.gt(vcf, element = "GT")
        geno_mat <- apply(geno_mat, 2, convert_to_dosage)
        rm(vcf) #Remove VCF
      }

      #} else {
      #Import genotype matrix
      # geno_mat <- read.csv(geno, header = TRUE, row.names = 1, check.names = FALSE)
      #}

      print(class(geno_mat))
      #Convert genotypes to alternate counts if they are the reference allele counts
      #Importantly, the dosage plot is based on the input format NOT the converted genotypes
      is_reference <- (input$zero_value == "Reference Allele Counts")
      convert_genotype_counts <- function(df, ploidy, is_reference = TRUE) {
        if (is_reference) {
          # Convert from reference to alternate alleles
          return(abs(df - ploidy))
        } else {
          # Data already represents alternate alleles
          return(df)
        }
      }

      print("Genotype file successfully imported")
      ######Get MAF plot (Need to remember that the VCF genotypes are likely set as 0 = homozygous reference, where the dosage report is 0 = homozygous alternate)

      #Updated MAF function
      calculateMAF <- function(df, ploidy) {
        if (is.matrix(df)) {
          df <- as.data.frame(df)
        }

        #Convert the elements to numeric if they are characters
        df[] <- lapply(df, function(x) if(is.character(x)) as.numeric(as.character(x)) else x)

        allele_frequencies <- apply(df, 1, function(row) {
          non_na_count <- sum(!is.na(row))
          allele_sum <- sum(row, na.rm = TRUE)
          #print(paste("Non-NA count:", non_na_count, "Allele sum:", allele_sum))
          if (non_na_count > 0) {
            allele_sum / (ploidy * non_na_count)
          } else {
            NA
          }
        })

        maf <- ifelse(allele_frequencies <= 0.5, allele_frequencies, 1 - allele_frequencies)

        df$AF <- allele_frequencies
        df$MAF <- maf

        maf_df <- df[,c("AF", "MAF"), drop = FALSE]

        #Make the row names (SNP ID) the first column
        maf_df <- maf_df %>%
          rownames_to_column(var = "SNP_ID")

        return(maf_df)
      }

      # Function to calculate percentages for each genotype in each sample
      calculate_percentages <- function(matrix_data, ploidy) {
        apply(matrix_data, 2, function(col) {
          counts <- table(col)
          prop <- prop.table(counts) * 100
          #max_val <- max(as.numeric(names(counts)))  # Find the maximum value in the column
          prop[as.character(0:ploidy)]  # Adjust the range based on the max value (consider entering the ploidy value explicitly for max_val)
        })
      }
      print("Starting percentage calc")
      #Status
      updateProgressBar(session = session, id = "pb_diversity", value = 70, title = "Calculating...")
      # Calculate percentages for both genotype matrices
      percentages1 <- calculate_percentages(geno_mat, ploidy)
      # Combine the data matrices into a single data frame
      percentages1_df <- as.data.frame(t(percentages1))
      percentages1_df$Data <- "Dosages"
      # Assuming my_data is your dataframe
      print("Percentage Complete: melting dataframe")
      melted_data <- percentages1_df %>%
        pivot_longer(cols = -(Data),names_to = "Dosage", values_to = "Percentage")

      diversity_items$dosage_df <- melted_data

      print("Dosage calculations worked")

      #Heterozygosity function
      calculate_heterozygosity <- function(genotype_matrix, ploidy = 2) {
        # Determine the heterozygous values based on ploidy
        heterozygous_values <- seq(1, ploidy - 1)

        # Create a logical matrix where TRUE represents heterozygous loci
        is_heterozygous <- sapply(genotype_matrix, function(x) x %in% heterozygous_values)

        # Count the number of heterozygous loci per sample, ignoring NAs
        heterozygosity_counts <- colSums(is_heterozygous, na.rm = TRUE)

        # Calculate the total number of non-NA loci per sample
        total_non_na_loci <- colSums(!is.na(genotype_matrix))

        # Compute the proportion of heterozygous loci
        heterozygosity_proportion <- heterozygosity_counts / total_non_na_loci

        # Create a dataframe with Sample ID and Observed Heterozygosity
        result_df <- data.frame(
          SampleID = colnames(genotype_matrix),
          ObservedHeterozygosity = heterozygosity_proportion,
          row.names = NULL,
          check.names = FALSE
        )

        return(result_df)
      }

      #Convert the genotype calls prior to het,af, and maf calculation
      geno_mat <- data.frame(convert_genotype_counts(df = geno_mat, ploidy = ploidy, is_reference),
                             check.names = FALSE)

      # Calculating heterozygosity for a tetraploid organism
      diversity_items$het_df <- calculate_heterozygosity(geno_mat, ploidy = ploidy)

      print("Heterozygosity success")
      diversity_items$maf_df <- calculateMAF(geno_mat, ploidy = ploidy)

      print("MAF success")

      #Updating value boxes
      output$mean_het_box <- renderValueBox({
        valueBox(
          value = round(mean(diversity_items$het_df$ObservedHeterozygosity),3),
          subtitle = "Mean Heterozygosity",
          icon = icon("dna"),
          color = "info"
        )
      })
      output$mean_maf_box <- renderValueBox({
        valueBox(
          value = round(mean(diversity_items$maf_df$MAF),3),
          subtitle = "Mean MAF",
          icon = icon("dna"),
          color = "info"
        )
      })

      #Status
      updateProgressBar(session = session, id = "pb_diversity", value = 100, title = "Complete!")
    })

    observe({
      req(diversity_items$dosage_df)

      #Plotting
      #pdf("alfalfa_11_GBS_and_Realignment_doubletons_filtered_dosages.pdf")
      box <- ggplot(diversity_items$dosage_df, aes(x=Dosage, y=Percentage, fill=Data)) +
        #geom_point(aes(color = Data), position = position_dodge(width = 0.8), width = 0.2, alpha = 0.5) +  # Add jittered points
        geom_boxplot(position = position_dodge(width = 0.8), alpha = 0.9) +
        labs(x = "\nDosage", y = "Percentage\n", title = "Genotype Distribution by Sample") +
        #scale_fill_manual(values = c("GBS loci" = "tan3", "DArTag Realignment loci" = "beige")) +
        theme_bw() +
        theme(
          axis.text = element_text(size = 14),
          axis.title = element_text(size = 14)
        )
      #dev.off()

      diversity_items$box_plot <- box
    })

    output$dosage_plot <- renderPlot({
      req(diversity_items$box_plot)
      diversity_items$box_plot
    })

    #Het plot
    output$het_plot <- renderPlot({
      req(diversity_items$het_df, input$hist_bins)

      #Plot
      #pdf("meng_filtered_alfalfa_11_GBS_DArTag_no_doubletons_sample_heterozygosity.pdf")
      hist(diversity_items$het_df$ObservedHeterozygosity, breaks = as.numeric(input$hist_bins), col = "tan3", border = "black", xlim= c(0,1),
           xlab = "Observed Heterozygosity",
           ylab = "Number of Samples",
           main = "Sample Observed Heterozygosity")

      axis(1, at = seq(0, 1, by = 0.1), labels = TRUE)

      #legend("topright", legend = c("GBS", "DArTag Realignment"),
      #     fill = c("tan3", "beige"),
      #     border = c("black", "black"))
      #dev.off()

    })

    #AF Plot
    output$af_plot <- renderPlot({
      req(diversity_items$maf_df, input$hist_bins)
      #Plot
      hist(diversity_items$maf_df$AF, breaks = as.numeric(input$hist_bins), col = "grey", border = "black", xlab = "Alternate Allele Frequency",
           ylab = "Frequency", main = "Alternate Allele Frequency Distribution")
    })

    #MAF plot
    output$maf_plot <- renderPlot({
      req(diversity_items$maf_df, input$hist_bins)

      #Plot
      hist(diversity_items$maf_df$MAF, breaks = as.numeric(input$hist_bins), col = "grey", border = "black", xlab = "Minor Allele Frequency (MAF)",
           ylab = "Frequency", main = "Minor Allele Frequency Distribution")
    })

    observe({
      req(diversity_items$het_df)
      output$sample_table <- renderDT({diversity_items$het_df}, options = list(scrollX = TRUE,autoWidth = FALSE, pageLength = 5))
    })

    observe({
      req(diversity_items$maf_df)
      output$snp_table <- renderDT({diversity_items$maf_df}, options = list(scrollX = TRUE,autoWidth = FALSE, pageLength = 5))

      #Plot
    })
    #Download Figures for Diversity Tab (Need to convert figures to ggplot)
    output$download_div_figure <- downloadHandler(

      filename = function() {
        if (input$div_image_type == "jpeg") {
          paste("genomic-diversity-", Sys.Date(), ".jpg", sep="")
        } else if (input$div_image_type == "png") {
          paste("genomic-diversity-", Sys.Date(), ".png", sep="")
        } else {
          paste("genomic-diversity-", Sys.Date(), ".tiff", sep="")
        }
      },
      content = function(file) {
        #req(all_plots$pca_2d, all_plots$pca3d, all_plots$scree, input$pca_image_type, input$pca_image_res, input$pca_image_width, input$pca_image_height) #Get the plots
        req(input$div_figure)

        if (input$div_image_type == "jpeg") {
          jpeg(file, width = as.numeric(input$div_image_width), height = as.numeric(input$div_image_height), res= as.numeric(input$div_image_res), units = "in")
        } else if (input$div_image_type == "png") {
          png(file, width = as.numeric(input$div_image_width), height = as.numeric(input$div_image_height), res= as.numeric(input$div_image_res), units = "in")
        } else {
          tiff(file, width = as.numeric(input$div_image_width), height = as.numeric(input$div_image_height), res= as.numeric(input$div_image_res), units = "in")
        }

        # Conditional plotting based on input selection
        if (input$div_figure == "Dosage Plot") {
          req(diversity_items$box_plot)
          print(diversity_items$box_plot)

        } else if (input$div_figure == "AF Histogram") {
          req(diversity_items$maf_df, input$hist_bins)

          #Plot
          hist(diversity_items$maf_df$AF, breaks = as.numeric(input$hist_bins), col = "grey", border = "black", xlab = "Alternate Allele Frequency",
               ylab = "Frequency", main = "Alternate Allele Frequency Distribution")

        } else if (input$div_figure == "MAF Histogram") {
          req(diversity_items$maf_df, input$hist_bins)

          #Plot
          hist(diversity_items$maf_df$MAF, breaks = as.numeric(input$hist_bins), col = "grey", border = "black", xlab = "Minor Allele Frequency (MAF)",
               ylab = "Frequency", main = "Minor Allele Frequency Distribution")

        } else if (input$div_figure == "OHet Histogram") {
          req(diversity_items$het_df, input$hist_bins)

          hist(diversity_items$het_df$ObservedHeterozygosity, breaks = as.numeric(input$hist_bins), col = "tan3", border = "black", xlim= c(0,1),
               xlab = "Observed Heterozygosity",
               ylab = "Number of Samples",
               main = "Sample Observed Heterozygosity")

          axis(1, at = seq(0, 1, by = 0.1), labels = TRUE)

        }

        dev.off()
      }

    )

    #Download files for Genotype Diversity
    output$download_div_file <- downloadHandler(
      filename = function() {
        paste0("genomic-diversity-results-", Sys.Date(), ".zip")
      },
      content = function(file) {
        # Temporary files list
        temp_dir <- tempdir()
        temp_files <- c()

        if (!is.null(diversity_items$het_df)) {
          # Create a temporary file for assignments
          het_file <- file.path(temp_dir, paste0("Sample-statistics-", Sys.Date(), ".csv"))
          write.csv(diversity_items$het_df, het_file, row.names = FALSE)
          temp_files <- c(temp_files, het_file)
        }

        if (!is.null(diversity_items$maf_df)) {
          # Create a temporary file for BIC data frame
          maf_file <- file.path(temp_dir, paste0("SNP-statistics-", Sys.Date(), ".csv"))
          write.csv(diversity_items$maf_df, maf_file, row.names = FALSE)
          temp_files <- c(temp_files, maf_file)
        }

        # Zip files only if there's something to zip
        if (length(temp_files) > 0) {
          zip(file, files = temp_files, extras = "-j") # Using -j to junk paths
        }

        # Optionally clean up
        file.remove(temp_files)
      }
    )
  })
}

## To be copied in the UI
# mod_diversity_ui("diversity_1")

## To be copied in the server
# mod_diversity_server("diversity_1")