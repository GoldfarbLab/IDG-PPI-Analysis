# Title     : annotate_filter
# Objective : Add GO annotation to the merged SAINT and CompPASS file
# Created by: Smaranda
# Created on: 9/3/2020

#if (!requireNamespace("BiocManager", quietly = TRUE))
#  install.packages("BiocManager")

#BiocManager::install("org.Hs.eg.db")

if(!dir.exists(file.path('output/', 'Prey_Prey_Interactions/'))){
  dir.create(file.path('output/', 'Prey_Prey_Interactions/'))
} else {
  FALSE
}

library(tidyverse)
library(org.Hs.eg.db)
library(DarkKinaseTools)
source("Cytoscape.R")
source("SiRNA_data.R")
#source("csnk1g_figures.R")

select <- get(x="select", pos = "package:dplyr")
#rename <- get(x = "rename", pos = "package:dplyr")

uniprot.mapping <- read_tsv("annotations/uniprot_mapping.tsv.zip")

st <- read.csv(file='output/Merge_CompPASS_SAINT.csv', header = TRUE, sep = ",", stringsAsFactors = FALSE)

#Bait Uniprot
#Grab Unique Baits
unique.Baits <- unique(st$Bait)

################################################################################
#Entrez GeneID

#Prey
# extract Prey Uniprot Identifier
data <- separate(data = st, col = `Prey`, into = c("First.Prey.Uniprot"), sep=";", remove=F, extra="drop")

# Remove isoform from the Prey Uniprot Identifier
data <- separate(data, "First.Prey.Uniprot", c("Canonical.First.Prey.Uniprot"), sep="-", remove=F, extra="drop")

# fill Prey Entrez GeneID
data <- left_join(data, uniprot.mapping, by=c("Canonical.First.Prey.Uniprot" = "UniProt"))

#Bait
## extract Bait Uniprot Identifier
data <- separate(data = data, col = `Bait`, into = c("First.Bait.Uniprot"), sep=";", remove=F, extra="drop")

# Remove isoform from the Bait Uniprot Identifier
data <- separate(data, "First.Bait.Uniprot", c("Canonical.First.Bait.Uniprot"), sep="-", remove=F, extra="drop")

# fill Bait Entrez GeneID
data <- left_join(data, uniprot.mapping, by=c("Canonical.First.Bait.Uniprot" = "UniProt"))

#Move and rename columns
data <- data[,c(1:7, 32:39, 8:31)]
data <- rename(data, c(Gene_Name.x = "Prey.Gene.Name", Gene_Synonym.x = "Prey.Gene.Synonym", GeneID.x = "Prey.GeneID", First_GeneID.x = "First.Prey.GeneID", 
                       Gene_Name.y = "Bait.Gene.Name", Gene_Synonym.y = "Bait.Gene.Synonym", GeneID.y = "Bait.GeneID", First_GeneID.y = "First.Bait.GeneID"))
data <- data[,c(1,12,13,2:4,14,15,8,9,5:7,10,11,16:39)]

################################################################################
#Annotations

xx <- as.list(org.Hs.egGO2ALLEGS)
x <-c("GO:0005634","GO:0005737","GO:0005856","GO:0005768","GO:0005783","GO:0005576","GO:0005794",
      "GO:0005764","GO:0005739","GO:0005777","GO:0005886","GO:0031982","GO:0005911")
go <- c("Nucleus","Cytoplasm","Cytoskeleton","Endosome","ER","Extracellular","Golgi","Lysosome",
        "Mitochondria","Peroxisome","Plasma_Membrane","Vesicles","Cell_Junction")


for(i in 1:length(go)) {
  goids <- xx[x[i]]
  goslim <- tibble(Prey.GeneID = goids[[1]], Evidence = names(goids[[1]]))
  #goslim <- filter(goslim, "IEA" != Evidence)
  goslim <- (goslim %>% 
               group_by(Prey.GeneID)%>% 
               summarise(n=n()))
  data <- left_join(data, goslim, by=c("Prey.GeneID" = "Prey.GeneID")) %>% 
    mutate(
      goNames = !is.na(n) 
    ) %>% 
    select(-`n`) %>% 
    rename(goNames = go[i])
}

#Merge GO Slim in Single Column
data$GO.Slim <- apply(data, 1, function(x) {
  str_c(go[as.logical(c(x[["Nucleus"]],x[["Cytoplasm"]],x[["Cytoskeleton"]], x[["Endosome"]], x[["ER"]],
                        x[["Extracellular"]], x[["Golgi"]], x[["Lysosome"]], x[["Mitochondria"]],
                        x[["Peroxisome"]], x[["Plasma_Membrane"]], x[["Vesicles"]], x[["Cell_Junction"]]))], 
        collapse = ";")
}
)

#Priority GO Column: Either matched with bait or from uniprot
#data$GO.Priority <- apply(data, 1, function(x)){
#}

#bait.data.filter <- data.filter %>% filter(Bait == mybait)
#num.interactors <- min(max(10, nrow(bait.data.filter)*0.05), nrow(bait.data.filter))
#all.data.filter <- all.data.filter %>% add_row(bait.data.filter[1:num.interactors, ])

#Annotate Dark Kinases
data <- left_join(data, all_kinases, by=c("First.Prey.GeneID" = "entrez_id"))

#Is it a Bait Column
data$is_Bait <- apply(data, 1, function(x) {
  any(str_detect(unique.Baits, x[["Canonical.First.Prey.Uniprot"]]))
}
)

#Nice bait name column addition by grabbing from prey name if it pairs with is_bait column
baitTable <- data %>%
  filter(is_Bait == TRUE) %>%
  filter(str_detect(Bait, Prey)) %>%
  select(Bait, BaitGene = PreyGene) %>%
  distinct() 

data <- left_join(data, baitTable, by="Bait")

################################################################################
#BioGrid Annotations

#Biogrid read  in
biogrid <- read.csv(file = 'C:/Users/smaranda/Documents/SmarandaSolomon/BIOGRID/BIOGRID-MV-Physical-4.4.203.tab3.txt', header = TRUE, sep="\t", stringsAsFactors = FALSE) %>%
  filter(Organism.ID.Interactor.A == 9606 & Organism.ID.Interactor.B == 9606)

#Is In BioGrid (T/F)
geneList = as.vector(data$`First.Prey.GeneID`[!is.na(data$`First.Prey.GeneID`)])

interactions <- biogrid %>%
  # select columns needed from bioGrid
  select(Entrez.Gene.Interactor.A, Entrez.Gene.Interactor.B) %>%
  # only take proteins with geneIDs
  filter(Entrez.Gene.Interactor.A != "-" & Entrez.Gene.Interactor.B != "-") %>% 
  # no self interactions
  filter(Entrez.Gene.Interactor.A != Entrez.Gene.Interactor.B) %>%
  # always putting the smaller geneID first
  mutate(interactor_min = pmin(as.numeric(Entrez.Gene.Interactor.A), as.numeric(Entrez.Gene.Interactor.B)), 
         interactor_max = pmax(as.numeric(Entrez.Gene.Interactor.A), as.numeric(Entrez.Gene.Interactor.B))) %>%
  select(interactor_min, interactor_max) %>%
  unique()

#CHANGE AS.NUMERIC AND PUT IT ABOVE SO IT GOES FASTER
data$in_BioGRID <- apply(data, 1, function(x) {
  nrow(filter(interactions, (`interactor_min` == as.numeric(x[["Prey.GeneID"]]) & `interactor_max` == as.numeric(x[["Bait.GeneID"]])) |
                (`interactor_max` == as.numeric(x[["Prey.GeneID"]]) & `interactor_min` == as.numeric(x[["Bait.GeneID"]]))
  )) > 0
}) 

################################################################################
#Filter SAINT

#Write file with no filter
write_csv(data, 'output/Annotated_Merge_NO_FILTER.csv')

#Filter SAINT
data.filter <- filter(data, BFDR <= 0.05, AvgP >= 0.7)

################################################################################
#Add SiRNA Data

sirna <- sirna.data()

data.filter <- left_join(data.filter, sirna, by = c("Prey.Gene.Name" = "Gene.Symbol"), copy = TRUE)

#Write file filtered for Saint
write_csv(data.filter, 'output/Annotated_Merge_Saint_filter.csv')

################################################################################
#Filter comppass and beyond

#Filter CompPASS
#Arrange first
data.filter.comp <- arrange(data.filter, desc(WD))

#Filter by top 5% or top min *KEEPING Everything*
baits <- unique((data.filter.comp %>% filter(!is.na(BaitGene), is_Bait == TRUE, BaitGene == PreyGene))$Bait)
all.data.filter <- data.filter.comp[0,]

#Create separate data tables for prey-prey interactions
for (mybait in baits) {
  
   #mybait <- "P24941"

  bait.data.filter <- data.filter.comp %>% filter(Bait == mybait)
  num.interactors <- min(max(10, nrow(bait.data.filter)*0.05), nrow(data.filter.comp))
  bait.data.filter.comp <- bait.data.filter[1:num.interactors, ]
  all.data.filter <- all.data.filter %>% add_row(bait.data.filter.comp)
  
  #Filtering for interactions
  prey.prey.inter <- filter(interactions, (`interactor_min` %in%  bait.data.filter.comp$First.Prey.GeneID), (`interactor_max` %in%  bait.data.filter.comp$First.Prey.GeneID)) %>%
    rename(c(interactor_min = "Prey.1.Entrez.ID", interactor_max = "Prey.2.Entrez.ID")) %>% #Changing column names
     mutate(Prey.1.Entrez.ID = as.character(Prey.1.Entrez.ID), 
            Prey.2.Entrez.ID = as.character(Prey.2.Entrez.ID)) #Changing data type from double to character to be left_joined with all.data.filter
  
  #Left_joining table with prey 1 and adding Uniprot and Nice Prey name columns
   prey.prey.join <- left_join(prey.prey.inter, bait.data.filter.comp, by=c("Prey.1.Entrez.ID" = "Prey.GeneID"))%>%
     select(Prey.1.Entrez.ID, Prey.2.Entrez.ID, Canonical.First.Prey.Uniprot, Prey.Gene.Name, WD) %>%
     rename(c(Canonical.First.Prey.Uniprot = "Prey.1.Uniprot", Prey.Gene.Name = "Prey.1.Gene.Name", WD = "WD.1"))

   #Left_joining table with prey 2 and adding Uniprot and Nice Prey name columns
   prey.prey.final <- left_join(prey.prey.join, bait.data.filter.comp, by=c("Prey.2.Entrez.ID" = "Prey.GeneID")) %>%
     select(Prey.1.Gene.Name, Prey.1.Uniprot, Prey.1.Entrez.ID, WD.1, Prey.Gene.Name, Canonical.First.Prey.Uniprot, Prey.2.Entrez.ID, WD) %>%
     rename(c(Canonical.First.Prey.Uniprot = "Prey.2.Uniprot", Prey.Gene.Name = "Prey.2.Gene.Name", WD = "WD.2")) %>%
     unique()

   #Add validation column (from Biogrid in this case) if dataframe has data in it
    if(nrow(prey.prey.final) != 0){
      prey.prey.final$Source <- 'Biogrid'
    }
   
   #write individual csv files for each bait
   write_csv(prey.prey.final, str_c('output/Prey_Prey_Interactions/', paste(unique(bait.data.filter$Bait.Gene.Name),"_",mybait,'.csv', sep = "")))
}

#Write file with filtered experiments, keeping everything
write_csv(all.data.filter, 'output/Annotated_Merge_All_filtered.csv')

################################################################################
#Filter by top 5% or top min *For DKK - no controls *
baits.dkk <- unique((data.filter.comp %>% filter(!is.na(BaitGene), is_Bait == TRUE, BaitGene == PreyGene, !is.na(class_2019)))$Bait)
all.data.dkk <- data.filter.comp[0,]

for (mybait in baits.dkk) {
  bait.data.filter <- data.filter.comp %>% filter(Bait == mybait)
  num.interactors <- min(max(10, nrow(bait.data.filter)*0.05), nrow(bait.data.filter))
  all.data.dkk <- all.data.dkk %>% add_row(bait.data.filter[1:num.interactors, ])
}

all.data.dkk <- all.data.dkk %>%
  dplyr::filter(!grepl('CSNK1G1|CSNK1G2|CSNK1G3', Experiment.ID))

################################################################################
#Write file with filtered experiments, only Dark kinases
write_csv(all.data.dkk, 'output/Annotated_Merge_filtered_DKK.csv')

cyto <- to.Cytoscape(all.data.filter, data)

#Write file with filtered experiments, only Dark kinases
write_csv(cyto, 'output/Cytoscape.csv')
