if(!require(Seurat)){
  remotes::install_version(package = 'Seurat', version = package_version('4.3.0'))
}
if(!require(SeuratDisk)){
  remotes::install_version(package = 'SeuratDisk')
}
if(!require(shiny)){
  remotes::install_version(package = 'shiny')
}
if(!require(ensembldb)){
  remotes::install_version(package = 'ensembldb')
}
if(!require(AnnotationHub)){
  remotes::install_version(package = 'AnnotationHub')
}

library(Seurat)
library(SeuratDisk)
library(shiny)
library(ensembldb)
library(AnnotationHub)

#Define the function to calculate the mitochondira percentage:
CalcMTPercent <- function(object, species){
  ah <- AnnotationHub()
  ahq <- query(ah,pattern = c(species, "EnsDb"), ignore.case = TRUE)
  ahq %>% 
    mcols()
  id <- ahq %>% 
    mcols() %>%
    rownames() %>% 
    tail(n = 1) 
  edb <- ah[[id]] 
  annotations <- genes(edb, return.type = "data.frame")
  annotations <- annotations %>%
    dplyr::select(gene_id, gene_name, seq_name)
  mt <- annotations %>%
    dplyr::filter(seq_name == "MT") %>% 
    dplyr::pull(gene_name) 
  mt1 <- annotations %>%
    dplyr::filter(seq_name == "MT") %>%
    dplyr::pull(gene_id)  
  mt <- c(mt,mt1)
  mt <- gsub('_','-',mt)
  object@meta.data$mtUMI <- Matrix::colSums(object[which(rownames(object) %in% mt),], na.rm = T) #This is to calculate the UMI count for mt gene in each cell and add them to the metadata
  object@meta.data$mitoPercent <- object@meta.data$mtUMI*100/object@meta.data$nCount_RNA #By dividing the total UMI count by mt UMI count, we can get mt percentage, which also can be added to the metadata of the SeuratObject
  object <- object #update the changed SeuratObject
}


# Define UI for dataset viewer app ----
ui <- fluidPage(
  
  # App title ----
  titlePanel("scRNA Data Visualization"),
  
  # Sidebar layout with input and output definitions ----
  sidebarLayout(
    
    # Sidebar panel for inputs ----
    sidebarPanel(
      
      h4("Introduction:"),
      h6("1. The original .h5 file generated by 10XGenomics can be used as input for this
      R shiny App. The file size should be less than 100 MB."),
      h6("2. The analysis is developed based on the Seurat R Package:
         https://satijalab.org/seurat/"),
      h6("3. The supported species for this App include mouse, human, rat, rhesus macaque, and zebra fish."),
      h6("4. The input dataset should be annotated by ENSEMBL, otherwise the filtration based on mitochondria percentage will not work."),
      h6("5. Ajustable Parameters for filtration:"),
      h6("5.1 Minimum number of cells expressing the gene: to exclude the genes that are sparsely expressed."),
      h6("5.2 Min and Max value of UMI cout, gene count and mitochondria percentage: to exclude the cells with bad quality."),
      h6("6. Parameters for clustering."),
      h6("6.1 The default normalization method is log normalization. (Not adjustable)"),
      h6("6.2 The clustering algorithm is graph based clustering. (Not adjustable)"),
      h6("6.3 The resolution and dimensionalities are adjustable for runing the clustering.
         Lower value might result in fewer clusters"),
      h6("7.Please ensure the input gene name is in capital to see its expression"),
      
      
      # Input: Species used to add mitochondria percentage
      selectInput(inputId = 'spe', 
                  label = 'Species', 
                  choices = c('Mus musculus','Homo sapiens','Rattus norvegicus','Macaca mulatta','Danio rerio')),
      
      # Input: filter the genes that will be used by using minimum number of cells expressing that gene
      numericInput(inputId = "min.cell",
                   label = "Minimum number of cells expressing the gene",
                   value = 10),
      
      # Input: Numeric entry for filtering based on desired min and max RNA count ----
      numericInput(inputId = "RNAcount_min",
                   label = "Minimum UMI count",
                   value = 400),
      numericInput(inputId = "RNAcount_max",
                   label = "Maxium UMI count",
                   value = 20000),
      
      # Input: Numeric entry for filtering based on desired min and max Gene count ----
      numericInput(inputId = "Genecount_min",
                   label = "Minium Gene count",
                   value = 400),
      numericInput(inputId = "Genecount_max",
                   label = "Maxium Gene count",
                   value = 10000),
      
      # Input: Numeric entry for filtering based on desired mitochondria Percentage ----
      numericInput(inputId = "Mtpercent",
                   label = "Maxium mt percentage (%)",
                   value = 10, min = 0, max = 100),
     
      # Input: Numeric entry for desired clustering resolution
      numericInput(inputId = "res",
                   label = "Resolution for clustering",
                   value = 0.5),
      # Input: Numberic entry for desired dimensionality used for clustering
      numericInput(inputId = "dim",
                   label = "Dimensionality for clustering",
                   value = 10),
      
      # Input: file entry for the SeuratObject that will be used
      fileInput(inputId = "file1",
                label = "Upload .h5 file",
                accept = ".h5"),
      
      # Input: Gene expression
      textInput(inputId = 'gene',
                label = 'Gene'),

    ),
    
    # Main panel for displaying outputs ----
    mainPanel(
      
      # Output: cell number before filtering ----
      h4('Number of cells before filtering'),
      verbatimTextOutput("num.before"),
      
      # Output: cell number after filtering ----
      h4('Number of cells after filtering'),
      verbatimTextOutput("num.after"),
      
      # Output: Quality control (QC) plots after filtering ----
      h4("QC plots after filtering"),
      plotOutput("plot1"),
      
      # Output:Cell clustering (UMAP) ----
      h4("Cell clusters (UMAP)"),
      plotOutput("plot2"),
      
      #Output: plots for gene expression ----
      h4("Gene Expression"),
      plotOutput("plot3"),
    )
  )
)

#Given the large size of scRNA data, here is to increase the size for uploading the file
options(shiny.maxRequestSize=500*1024^2) 
server <- function(input, output) {

# read the .h5 file
  datasetinput <- reactive({
   infile <- input$file1
   Read10X_h5(infile$datapath)
  })
  
# Create seurat object
  seurat <- reactive(
    CreateSeuratObject(datasetinput(), min.cells = input$min.cell)
    )
# New data set aftering filtering the cells with bad quality
  dataset1 <- reactive({
    data <- seurat()
    data <- CalcMTPercent(data, input$spe)
    data <- subset(data, subset = nCount_RNA > input$RNAcount_min & nCount_RNA < input$RNAcount_max
           & nFeature_RNA >input$Genecount_min & nFeature_RNA < input$Genecount_max & mitoPercent< input$Mtpercent)
    data <- NormalizeData(data)
    data <- ScaleData(data, features = rownames(data))
    data <- FindVariableFeatures(data, selection.method = "vst", nfeatures = 2000)
    data <- RunPCA(data, features = VariableFeatures(object = data))
    data <- FindNeighbors(data, dims = 1:input$dim)
    data <- FindClusters(data, resolution = input$res)
    data <- RunUMAP(data, dims = 1:input$dim)
    })

# Output: number of cells in this dataset before filtering  
  output$num.before <- renderPrint(
    ncol(seurat())
  )
  
# Output: number of cells in this dataset after filtering  
  output$num.after <- renderPrint({
    ncol(dataset1())
  })
  
# Output: QC plot (distributionn of UMI count, gene count and mitochondir percentage) after filtering 
  output$plot1 <- renderPlot(
    VlnPlot(dataset1(), features = c('nCount_RNA','nFeature_RNA','mitoPercent'), ncol = 3)
  )

#Output: Umap for cell clustering
  output$plot2 <- renderPlot(
    DimPlot(dataset1(), reduction = 'umap')
  )
  
# output: Gene expression plot
  output$plot3 <- renderPlot({
    x <- as.vector(input$gene)
    data <- dataset1()
    VlnPlot(data, features = x)
  })
}

shinyApp(ui, server)


