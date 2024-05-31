if(!require(trelloR)) {install.packages("trelloR"); library(trelloR)}
if(!require(purrr)) {install.packages("purrr"); library(purrr)}
if(!require(dplyr)) {install.packages("dplyr"); library(dplyr)}
if(!require(writexl)) {install.packages("writexl"); library(writexl)}
if(!require(stringr)) {install.packages("stringr"); library(stringr)}
if(!require(tidyr)) {install.packages("tidyr"); library(tidyr)}
if(!require(lubridate)) {install.packages("lubridate"); library(lubridate)}
if(!require(httpuv)) {install.packages("httpuv"); library(httpuv)}
# At the end of this script there's a commented out list of packages and the
# imported functions from them used

# Set up the Trello API connection and get the id for the board -----------
my_token = get_token("my-app",
                     key = Sys.getenv("MY_TRELLOAPI_KEY"), 
                     secret = Sys.getenv("MY_TRELLOAPI_SECRET"))

the_board <- get_my_boards() %>% 
  filter(name == "Application Tracker") %>% 
  pull(id)


# Set up lookup tables for list and label ids for the names ---------------

the_list_ids <- get_board_lists(the_board) %>% 
  select(id, name) %>% 
  rename(list=name, idList=id)

the_label_ids <- get_board_labels(the_board) %>% 
  select(id, name) %>% 
  rename(label=name)


# Grab the cards ----------------------------------------------------------

the_cards <- get_board_cards(the_board) %>% 
  select(id,idList,idLabels,name,due,shortUrl,desc)

# Figure out the labels for each card -------------------------------------

# The label ids are embedded in a list ordered by card, so we need to flatten
# the list as a vector and then a single-column data frame while still 
# preserving the null slots with no label. This way the associations line up.
assigned_labels <- the_cards$idLabels %>% 
  map_if(is_empty, length) %>% 
  map_if(is.integer, as.character) %>% 
  list_c() %>% 
  as.data.frame(nm="id")

# Replace the ids with the actual label names in another 1-column data frame
# that lines up each label name with the right card. Merge this into the data 
# frame of cards
ordered_labels <- left_join(assigned_labels, the_label_ids) %>% 
  select(-id)

the_cards <- bind_cols(the_cards, ordered_labels) %>% 
  select(-idLabels)


# Look up and replace the list ids ----------------------------------------

the_cards <- left_join(the_cards, the_list_ids) %>% 
  select(-idList)

# Split the name field into Job and Company -------------------------------

the_cards <- the_cards %>% 
  mutate(name = str_replace(name, "\\(([^)]+)\\) ", "\\1: ")) %>% 
  separate(name, into=c("Company","Job"), sep=": ", extra="merge", fill="right")


# Add card created date ---------------------------------------------------

# Use the trick that the first 8 characters of the card id are a timestamp 
# as a hex number of when the card was created

the_cards <- the_cards %>% 
  mutate(timestamp = strtoi(substring(id, 1, 8), base=16)) %>% 
  mutate(CardCreated = as.Date(as.POSIXct(timestamp, origin = "1970-01-01"))) %>% 
  select(-timestamp)


# Extract info from the Trello description field --------------------------

## The first four lines (Markdown) are reserved for set fields to extract

LinkToJob <- str_split_i(the_cards$desc, "\n", 1) %>% 
  str_remove(., "^- \\*\\*Link:\\*\\* ") %>% 
  str_extract(., "^\\[(.*)\\]") %>% 
  str_remove_all(., "\\[|\\]")

Location <- str_split_i(the_cards$desc, "\n", 2) %>%
  str_remove(., "^- \\*\\*Location:\\*\\* ") 

InterviewedLast <- str_split_i(the_cards$desc, "\n", 3) %>%
  str_remove(., "^- \\*\\*Interview Date:\\*\\*") %>% 
  as.Date(., format = "%m/%d/%Y")

Rejected <- str_split_i(the_cards$desc, "\n", 4) %>%
  str_remove(., "^- \\*\\*Rejected Date:\\*\\* ") %>% 
  as.Date(., format = "%m/%d/%Y")

## Put anything else in the description field into a separate column

the_cards$OtherNotes <- lapply(
  str_split(the_cards$desc, "\n"), 
  function(x)  str_flatten(x[5:length(x)])) %>% 
  unlist()

## Combine the extracted fields into a data frame and add the columns in

FromNotes <- data.frame(LinkToJob, Location, InterviewedLast, Rejected)

the_cards <- bind_cols(the_cards, FromNotes) %>% 
  select(-desc)

# Clean up, sort, and save as Excel ---------------------------------------

the_cards <- select(the_cards, -id) %>% 
  mutate(ApplyDate=as.Date(due),
         ApplyWeek=ifelse(is.na(ApplyDate),
                          "",
                          paste0(year(ceiling_date(ApplyDate, unit = "week", 
                                                   week_start="Sunday") - days(1)),
                                 sprintf("%02d", epiweek(ApplyDate)))),
         .keep="unused") %>% 
  select(Job, Company, ApplyDate, ApplyWeek, Status=list, 
         LocationType=label, LinkToCard=shortUrl, LinkToJob, Location, InterviewedLast, Rejected, OtherNotes, CardCreated) %>%
  filter(Status %in% c("Create/Prep","Applied/Submitted","Interview",
                       "Rejected","No Response")) %>% 
  group_by(ApplyDate) %>% 
  arrange(ApplyDate)

the_cards %>% 
  mutate(LinkToCard = xl_hyperlink(LinkToCard,"X"), 
         LinkToJob = xl_hyperlink(LinkToJob,"X"),
         .keep="unused") %>% 
  write_xlsx("ApplicationTracker.xlsx")

# Save the_cards as an RDS file for use in further processing -------------
saveRDS(the_cards, "the_cards.rds")


# Packages and the functions used in the script imported from them --------

# Using NCmisc::list.functions.in.file()

# $`c("package:dplyr", "package:stats")`
# [1] "filter"
# 
# $`package:dplyr`
# [1] "arrange"   "bind_cols" "group_by"  "left_join" "mutate"    "pull"     
# [7] "rename"    "select"   
# 
# $`package:lubridate`
# [1] "ceiling_date" "days"         "epiweek"      "year"        
# 
# $`package:purrr`
# [1] "list_c" "map_if"
# 
# $`package:stringr`
# [1] "str_extract"    "str_flatten"    "str_remove"     "str_remove_all"
# [5] "str_replace"    "str_split"      "str_split_i"   
# 
# $`package:tidyr`
# [1] "separate"
# 
# $`package:trelloR`
# [1] "get_board_cards"  "get_board_labels" "get_board_lists" 
# [4] "get_my_boards"    "get_token"       
# 
# $`package:utils`
# [1] "install.packages"
# 
# $`package:writexl`
# [1] "write_xlsx"   "xl_hyperlink"

