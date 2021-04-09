# control of the pipeline
configfile: "config/config.yaml"
# sample metadata and information
pepfile: "pep/config.yaml"

## GLOBAL HELPER FUNCTIONS
def samples(pep):
    """
    Get all of the unique sample names
    """
    return pep.sample_table["sample_name"]

def lookup_sample_metadata(sample, key, pep):
    """
    Get sample metadata by key
    """
    return pep.sample_table.at[sample, key]

def lookup_in_config(config, keys, default = None):
    curr_dict = config
    try:
        for key in keys:
            curr_dict = curr_dict[key]
        value = curr_dict
    except KeyError:
        if default is not None:
            logger.warning("No value found for keys: '%s' in config file. Defaulting to %s"%(", ".join(keys), default))
            value = default
        else:
            logger.error("No value found for keys: '%s' in config.file"%(",".join(keys)))
            raise KeyError
    return value


def lookup_in_config_persample(config, pep, keys, sample, default = None):
    """
    This is a special case of looking up things in the config file for
    a given sample. First check for if column is specified. Then
    check if value is specified
    """
    param_info = lookup_in_config(config, keys, default)
    if type(param_info) is dict:
        if "column" in param_info.keys():
            outval = lookup_sample_metadata(sample, param_info["column"], pep)
        elif "value" in param_info.keys():
            outval = param_info["value"]
        else:
            logger.info("No value or column specifier found for keys: '%s' in config file. Defaulting to %s"%(", ".join(keys), default))
            outval = default

    else:
        logger.info("No value or column specifier found for keys: '%s' in config file. Defaulting to %s"%(", ".join(keys), default))
        outval = default
    return outval
            

def determine_extracted_samples(pep):
    samp_table = pep.sample_table
    samples = samp_table.loc[~samp_table["input_sample"].isna(), "sample_name"]
    return samples.tolist()

def filter_samples(pep, filter_text):
    samp_table = pep.sample_table
    #samples = samp_table.loc[samp_table.eval(filter_text), "sample_name"] 
    samples = samp_table.query(filter_text)["sample_name"]
    return samples.tolist()


def determine_effective_genome_size_file(sample, config, pep):
    genome = lookup_sample_metadata(sample, "genome", pep)
    return "results/alignment/combine_fasta/%s/%s_mappable_size.txt"%(genome, genome)

def determine_effective_genome_size(sample, config, pep):
    infile = determine_effective_genome_size_file(sample, config, pep)
    with open(infile, mode = "r") as inf:
        size = inf.readline().rstrip()  
    return size

def determine_masked_regions_file(config, genome):
    if "masked_regions" in config["reference"][genome]:
        outfile = config["reference"][genome]["masked_regions"]
    else:
        outfile = None
    return outfile


def determine_final_normalization(config):
    ending = "log2ratio"
    if "coverage_and_norm" in config and "RobustZ" in config["coverage_and_norm"]:
        RZ = config["coverage_and_norm"]["RobustZ"]
        if RZ:
            ending += "RZ"
    return ending

def determine_pseudocount(config):
    if "coverage_and_norm" in config and "pseudocount" in config["coverage_and_norm"]:
        pseudocount = config["coverage_and_norm"]["pseudocount"]
    else:
        logger.warning(
        """
        Could not find specification for a pseudocount in config file. I.e.

        normalization:
            pseudocount: 1

        defaulting to a pseudocount of 0
        """)
        pseudocount = 0
    return pseudocount
    
RES = lookup_in_config(config, ["coverage_and_norm", "resolution"], 5)
WITHIN = lookup_in_config(config, ["coverage_and_norm", "within"], "median")
ENDING = determine_final_normalization(config)

# include in several rules here
include: "workflow/rules/preprocessing.smk"
include: "workflow/rules/alignment.smk"
include: "workflow/rules/coverage_and_norm.smk"
include: "workflow/rules/quality_control.smk"
include: "workflow/rules/peak_calling.smk"
include: "workflow/rules/postprocessing.smk"



## overall rules

rule run_all:
    input: 
        "results/quality_control/multiqc_report.html",
        expand("results/peak_calling/cmarrt/{sample}_{within}_{ending}.narrowPeak",\
        sample = determine_extracted_samples(pep),\
        within = WITHIN,\
        ending = ENDING),
        expand("results/peak_calling/macs2/{sample}_peaks.xls",\
        sample = determine_extracted_samples(pep))

rule clean_all:
    threads: 1
    shell:
        "rm -rf results/"    
