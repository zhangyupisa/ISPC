
####################################################################
###
### This Script calculates 
### 
### Input data:
### ("./3_DataProcessing/",download.method,"/",Cancer,"/SurvivalData/")
### Output data are saved as Rdata file:
#####################################################################

# Before running this script, first download TCGA assembler 2.0.3 scripts http://www.compgenome.org/TCGA-Assembler/
# Setup environment
rm(list=ls())

setwd("~/Dropbox (TBI-Lab)/TCGA Analysis pipeline/")                                                                    # Setwd to location were output files have to be saved.
code_path = "~/Dropbox (Personal)/Jessica PhD Project/QCRI-SIDRA-ICR-Jessica/"                                          # Set code path to the location were the R code is located

source(paste0(code_path, "R tools/ipak.function.R"))

required.packages = c("survival","reshape","ggplot2","plyr","Rcpp","colorspace","texreg")
required.bioconductor.packages = "survival"
ipak(required.packages)
ibiopak(required.bioconductor.packages)

source(paste0(code_path, "R tools/ggkm_v4.R"))

# Set Parameters
CancerTYPES = "ALL"                                                                                                     # Specify the cancertypes that you want to download or process, c("...","...") or "ALL"
Cancer_skip = c("")                                                                                                        # If CancerTYPES = "ALL", specify here if you want to skip cancertypes
download.method = "Assembler_Panca_Normalized_filtered"                                                                                      # Specify download method (this information to be used when saving the file)
assay.platform = "gene_RNAseq" 
Log_file = paste0("./1_Log_Files/", download.method ,"/3.13_Survival_Analysis/3.13_Survival_Analysis_Log_File_",                              # Specify complete name of the logfile that will be saved during this script
                  gsub(":",".",gsub(" ","_",date())),".txt")
ICR_k = "HML_classification"                                                                                            # "HML_classification" or "k3" or "k4" or "k5"
Surv_cutoff_years = 10
Source_surv_data = "Cell_paper"
Outcome = "OS"

# Load data
#load(paste0(code_path, "Datalists/ICR_genes.RData")) 
TCGA.cancersets = read.csv(paste0(code_path, "Datalists/TCGA.datasets.csv"),stringsAsFactors = FALSE)                   # TCGA.datasets.csv is created from Table 1. (Cancer Types Abbreviations) 

# Create folders
dir.create("./4_Analysis/",showWarnings = FALSE)                                                                        # Create folder to save processed data (by Assembler module B)
dir.create(paste0("./4_Analysis/",download.method),showWarnings = FALSE)
dir.create(paste0("./1_Log_Files/"), showWarnings = FALSE)                                                              # Create folder to save logfile
dir.create(paste0("./1_Log_Files/", download.method), showWarnings = FALSE)  
dir.create(paste0("./1_Log_Files/", download.method ,"/3.13_Survival_Analysis/"), showWarnings = FALSE)
cat("This is a log file for Survival Analysis of ",                                                                     # Set-up logfile
    "__________________________________________",
    "",
    "Session Info :",
    capture.output(sessionInfo()),
    "",
    "Script Running Date :",
    capture.output(Sys.time()),
    "",
    "Parameters Used :",
    paste0("CancerTYPES = ", CancerTYPES),                                                          
    paste0("Cancer_skip = ", Cancer_skip),
    paste0("download.method = ", download.method),
    "",
    "Scripts output :",
    "",
    "Clustering",
    file = Log_file,
    append = FALSE, sep= "\n")

# Define parameters (based on loaded data)
if (CancerTYPES == "ALL") { 
  CancerTYPES <- TCGA.cancersets$cancerType
}

All_survival_analysis_data = data.frame(Cancertype = CancerTYPES, p_value = 0, HR=0 , CI_lower=0, CI_upper = 0)

N.sets = length(CancerTYPES)

## Perform survival analysis
start.time.process.all = Sys.time()
msg = paste0("Analyzing", "\n")
cat(msg)

i = 3
for (i in 1:N.sets) {
  start.time.process.cancer = Sys.time()
  Cancer = CancerTYPES[i]
  if (Cancer %in% Cancer_skip) {next}
  cat (paste0 ("Survival Analysis for ",Cancer,"."))
  if(Cancer == "LAML") 
  {cat(paste0("For ", Cancer, ", a normalization file does not exist, file is skipped.", 
              "\n",
              "-----------------------------------------------------------------------------------------------------------",
              "\n"), file = Log_file, sep = "\n", append = TRUE)
    next}
  Cluster_file = paste0("./4_Analysis/", download.method, "/", Cancer, "/clustering/", Cancer, ".", download.method, ".EDASeq.ICR.reps5000/",
                        Cancer, "_ICR_cluster_assignment_k2-6.Rdata")
  load(Cluster_file)
  
  if(Source_surv_data == "TCGA_Assembler"){
    Survival_data = read.csv(paste0("./3_DataProcessing/TCGA_Assembler/",Cancer,"/SurvivalData/updatedsurvivaldata.csv"))
  }
  if(Source_surv_data == "Cell_paper"){
    Survival_data = read.csv("./2_Data/TCGA cell 2018 clinical/TCGA_CLINICAL_DATA_CELL_2018_S1.csv",
                             stringsAsFactors = FALSE)
    colnames(Survival_data)[which(colnames(Survival_data) == "death_days_to")] = "days_to_death"
    colnames(Survival_data)[which(colnames(Survival_data) == "last_contact_days_to")] = "days_to_last_followup"
  }
  
  # Create folders to save the data
  dir.create(paste0("./4_Analysis/",download.method,"/Pan_Cancer"),showWarnings = FALSE)
  dir.create(paste0("./4_Analysis/",download.method,"/Pan_Cancer/Survival_Analysis"),showWarnings = FALSE)
  dir.create(paste0("./5_Figures"), showWarnings = FALSE)
  dir.create(paste0("./5_Figures/Kaplan_Meier_Plots"), showWarnings = FALSE)
  dir.create(paste0("./5_Figures/Kaplan_Meier_Plots/", ICR_k), showWarnings = FALSE)
  dir.create(paste0("./5_Figures/Kaplan_Meier_Plots/", ICR_k, "/", download.method), showWarnings = FALSE)
  
  if(ICR_k == "HML_classification"){
    Survival_data$ICR_cluster = table_cluster_assignment$HML_cluster[match(Survival_data$bcr_patient_barcode,substring(rownames(table_cluster_assignment),1,12))]
    Survival_data = Survival_data[!is.na(Survival_data$ICR_cluster),]
    Survival_data = Survival_data[-which(Survival_data$ICR_cluster == "ICR Medium"),] # exclude ICR medium samples
    Survival_data$ICR_cluster = factor(Survival_data$ICR_cluster, levels = c("ICR High", "ICR Low")) 
    Highest_ICR_group = "ICR High"
  }
  
  if(ICR_k == "k3"){
    Survival_data$ICR_cluster = table_cluster_assignment$ICR_cluster_k3[match(Survival_data$bcr_patient_barcode,substring(rownames(table_cluster_assignment),1,12))]
    Survival_data = Survival_data[!is.na(Survival_data$ICR_cluster),]
    Survival_data$ICR_cluster = as.character(Survival_data$ICR_cluster)
    Survival_data$ICR_cluster[Survival_data$ICR_cluster == "ICR1"] = "ICR Low"
    Survival_data$ICR_cluster[Survival_data$ICR_cluster == "ICR3"] = "ICR High"
  }
  
  if(ICR_k == "k4"){
    Survival_data$ICR_cluster = table_cluster_assignment$ICR_cluster_k4[match(Survival_data$bcr_patient_barcode,substring(rownames(table_cluster_assignment),1,12))]
    Survival_data = Survival_data[!is.na(Survival_data$ICR_cluster),]
    Survival_data$ICR_cluster = as.character(Survival_data$ICR_cluster)
    Survival_data$ICR_cluster[Survival_data$ICR_cluster == "ICR1"] = "ICR Low"
    Survival_data$ICR_cluster[Survival_data$ICR_cluster == "ICR4"] = "ICR High"
  }
  
  if(ICR_k == "k5"){
    Survival_data$ICR_cluster = table_cluster_assignment$ICR_cluster_k5[match(Survival_data$bcr_patient_barcode,substring(rownames(table_cluster_assignment),1,12))]
    Survival_data = Survival_data[!is.na(Survival_data$ICR_cluster),]
    Survival_data$ICR_cluster = as.character(Survival_data$ICR_cluster)
    Survival_data$ICR_cluster[Survival_data$ICR_cluster == "ICR1"] = "ICR Low"
    Survival_data$ICR_cluster[Survival_data$ICR_cluster == "ICR5"] = "ICR High"
  }
  
  Y = Surv_cutoff_years * 365
  TS.EventFree = Survival_data[Survival_data[, Outcome] == "0", c(Outcome, paste0(Outcome, ".time"), "ICR_cluster")]
  colnames(TS.EventFree) = c("Status","Time", "Group")
  TS.EventFree$Time = as.numeric(as.character(TS.EventFree$Time))
  TS.EventFree$Time[TS.EventFree$Time > Y] = Y
  
  TS.EventOccured = Survival_data[Survival_data[, Outcome] == "1", c(Outcome, paste0(Outcome, ".time"), "ICR_cluster")]
  colnames(TS.EventOccured) = c("Status","Time", "Group")
  TS.EventOccured$Time = as.numeric(as.character(TS.EventOccured$Time))
  TS.EventOccured$Status[which(TS.EventOccured$Time> Y)] = "EventFree"
  TS.EventOccured$Time[TS.EventOccured$Time > Y] = Y
  
  TS.Surv = rbind (TS.EventOccured,TS.EventFree)
  TS.Surv$Time = as.numeric(as.character(TS.Surv$Time))
  TS.Surv$Status <- TS.Surv$Status == "1"
  TS.Surv = subset(TS.Surv,TS.Surv$Time > 1)                                                                                         # remove patients with less then 1 day follow up time
  
  # survival curve
  msurv = Surv(TS.Surv$Time/30.4, TS.Surv$Status)                                                                                    # calculate the number of months
  mfit = survfit(msurv~TS.Surv$Group,conf.type = "log-log")
  
  # Calculations
  mdiff = survdiff(eval(mfit$call$formula), data = eval(mfit$call$data))
  pval = pchisq(mdiff$chisq,length(mdiff$n) - 1,lower.tail = FALSE)
  pvaltxt = ifelse(pval < 0.0001,"p < 0.0001",paste("p =", signif(pval, 3)))
  
  #TS.Surv[,"Group"] = factor(TS.Surv[,"Group"], levels = c("ICR High", "ICR Medium", "ICR Low"))
  TS.Surv[,"Group"] = as.factor(TS.Surv[,"Group"])
  
  # Check this!!
  ##TS.Surv[,"Group"] = relevel(TS.Surv[,"Group"], "ICR High")
  mHR = coxph(formula = msurv ~ TS.Surv[,"Group"],data = TS.Surv, subset = TS.Surv$Group %in% c("ICR High", "ICR Low"))
  mHR.extract = extract.coxph(mHR, include.aic = TRUE,
                              include.rsquared = TRUE, include.maxrs=TRUE,
                              include.events = TRUE, include.nobs = TRUE,
                              include.missings = TRUE, include.zph = TRUE)
  HRtxt = paste("Hazard-ratio =", signif(exp(mHR.extract@coef),3),"for",names(mHR$coefficients))
  beta = coef(mHR)
  se   = sqrt(diag(mHR$var))
  p    = 1 - pchisq((beta/se)^2, 1)
  CI   = confint(mHR)
  CI   = round(exp(CI),2)
  
  ## extract only ICR High vs. ICR Low
  All_survival_analysis_data[All_survival_analysis_data == Cancer, "p_value"] = p[1]
  All_survival_analysis_data[All_survival_analysis_data == Cancer, "HR"] = signif(exp(mHR.extract@coef),3)[1]
  All_survival_analysis_data[All_survival_analysis_data == Cancer, "CI_lower"] = CI[1,1]
  All_survival_analysis_data[All_survival_analysis_data == Cancer, "CI_upper"] = CI[1,2]
  
  PLOT_P = signif(p[1], digits = 3)
  PLOT_HR = round(signif(exp(mHR.extract@coef),3)[1], 3)
  PLOT_CI1 = CI[1,1]
  PLOT_CI2 = CI[1,2]
  
  # plots
  png(paste0("./5_Figures/Kaplan_Meier_Plots/", ICR_k, "/", download.method, "/", Source_surv_data, "_", Outcome,"_Kaplan_Meier_", ICR_k, "_", Cancer, "_figure1_legends.png"),
      res=600, height=3,width=4,unit="in")                                                                                           # set filename
  ggkm(mfit,
       timeby=12,
       ystratalabs = levels(TS.Surv[,"Group"]),
       ystrataname = NULL,
       main= paste0(Cancer, "\n"),
       xlabs = "Time in months",
       cbPalette = cbPalette)
       #PLOT_HR = PLOT_HR,
       #PLOT_P = PLOT_P,
       #PLOT_CI1 = PLOT_CI1,
       #PLOT_CI2 = PLOT_CI2)
  dev.off()
  
  #####
  end.time.process.cancer <- Sys.time ()
  time = substring(as.character(capture.output(round(end.time.process.cancer - start.time.process.cancer, 2))),20,100)
  msg = paste0("Processing time for ", Cancer, ": ", time, ".")
  cat(msg)
  cat(msg, file = Log_file, sep = "\n",append=TRUE)
}

#save(All_survival_analysis_data, 
     #file = paste0("./4_Analysis/",download.method,"/Pan_Cancer/Survival_Analysis/", Outcome, "_",Source_surv_data, "_Survival_analysis_High_vs_Low_Groups", ICR_k, ".Rdata"))

end.time.process.all <- Sys.time ()
time <- substring(as.character(capture.output(round(end.time.process.all - start.time.process.all, 2))),20,100)
msg = paste0("\n","Processing time for all cancertypes: ",time, " min.", "\n", "---------------------------------------------------------------")
cat(msg)
cat(msg, file = Log_file,"",sep = "\n",append=TRUE)
