if(!require(trelloR)) {install.packages("trelloR"); library(trelloR)}
if(!require(purrr)) {install.packages("purrr"); library(purrr)}
if(!require(dplyr)) {install.packages("dplyr"); library(dplyr)}
if(!require(writexl)) {install.packages("writexl"); library(writexl)}
if(!require(stringr)) {install.packages("stringr"); library(stringr)}
if(!require(tidyr)) {install.packages("tidyr"); library(tidyr)}
if(!require(lubridate)) {install.packages("lubridate"); library(lubridate)}
if(!require(httpuv)) {install.packages("httpuv"); library(httpuv)}
if(!require(readr)) {install.packages("readr"); library(readr)}

options <- list(outputs = "all", #"all" OR "no_cvs"
                use = "My Application Tracker" #"My Application Tracker"[your board name] OR "Sample Application Tracker"
                ) 

# Set up the Trello API connection and get the id for the board -----------

if (options$use == "Sample Application Tracker") {
  the_board <- "669186af27d6aa1627b818ae" 
} else {
  
# I use a local .Renviron file in the project folder to store the key
# and secret

my_token = get_token("my-app",
                     key = Sys.getenv("MY_TRELLOAPI_KEY"), 
                     secret = Sys.getenv("MY_TRELLOAPI_SECRET"))

the_board <- get_my_boards() %>% 
  filter(name == eval(options$use)) %>% 
  pull(id) 
}

if (length(the_board)==0) stop(paste0(eval(options$use)," not found. Spelling?"))


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

# Use the fact that the first 8 characters of the card id are a timestamp 
# as a hex number of when the card was created in GMT. It will have to be converted 
# to the local time zone that all the other date / time values are in.
# Link: https://support.atlassian.com/trello/docs/getting-the-time-a-card-or-board-was-created/
the_cards <- the_cards %>% 
  mutate(timestamp = strtoi(substring(id, 1, 8), base=16)) %>% 
  mutate(CardCreated = as.Date(format(with_tz(as.POSIXct(timestamp, origin = "1970-01-01"),tz=Sys.timezone())))) %>% 
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

the_cards <- the_cards %>% 
  mutate(ApplyDate=as.Date(due),
         ApplyWeek=as.character(floor_date(ApplyDate, unit = "week", week_start="Sunday")),
         LinkToCompany=paste0("https://duckduckgo.com/html?q=\'",
                              URLencode(Company, TRUE),
                              " company\'")) %>% 
  select(Job, Company, ApplyDate, ApplyWeek, Status=list, 
         WorkModel=label, LinkToCard=shortUrl, LinkToJob, LinkToCompany, Location, 
         InterviewedLast, Rejected, OtherNotes, CardCreated, TrelloCardID = id) %>%
  arrange(ApplyDate)

the_cards %>% 
  mutate(
    LinkToCard = xl_hyperlink(LinkToCard,"card"), 
    LinkToJob = xl_hyperlink(LinkToJob,"listing"),
    LinkToCompany = xl_hyperlink(LinkToCompany,"company")) %>% 
  write_xlsx("ApplicationTracker.xlsx")

# Save the_cards as an RDS file for use in further processing -------------
saveRDS(the_cards, "the_cards.rds")

if(options$outputs=="all") write_csv(the_cards, "the_cards.csv")


