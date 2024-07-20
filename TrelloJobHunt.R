if(!require(trelloR)) {install.packages("trelloR"); library(trelloR)}
if(!require(purrr)) {install.packages("purrr"); library(purrr)}
if(!require(dplyr)) {install.packages("dplyr"); library(dplyr)}
if(!require(stringr)) {install.packages("stringr"); library(stringr)}
if(!require(tidyr)) {install.packages("tidyr"); library(tidyr)}
if(!require(lubridate)) {install.packages("lubridate"); library(lubridate)}
if(!require(httpuv)) {install.packages("httpuv"); library(httpuv)}
if(!require(readr)) {install.packages("readr"); library(readr)}
if(!require(openxlsx)) {install.packages("openxlsx"); library(openxlsx)}

options <- list(board_to_use = "My Application Tracker" 
                # "Sample Application Tracker"  OR 
                # "My Application Tracker"[can be your board name]
                ) 

# Get the id for the board to use -----------------------------------------

if (options$board_to_use == "Sample Application Tracker") {
  # for a public board like the sample board you just need the board id
  the_board <- "669186af27d6aa1627b818ae" 
} else {
  
# I use a local .Renviron file in the project folder to store the key
# and secret for using my actual private board for job hunting

my_token = get_token("my-app", 
                     key = Sys.getenv("MY_TRELLOAPI_KEY"), 
                     secret = Sys.getenv("MY_TRELLOAPI_SECRET"),
                     expiration = "never")

the_board <- get_my_boards() %>% 
  filter(name == eval(options$board_to_use)) %>% 
  pull(id) 
}

if (length(the_board)==0) stop(paste0("\"", eval(options$board_to_use),"\" not found. Spelling?"))


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

# Clean up and sort -------------------------------------------------------

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

# Save the_cards out as an Excel file -------------

# create a data frame version of "the_cards" with link columns set to 
# appropriate Excel formula text

df <- the_cards %>%
  mutate(
    LinkToCard = paste0("=HYPERLINK(\"", LinkToCard, "\", \"card\")"),
    LinkToJob = paste0("=HYPERLINK(\"", LinkToJob, "\", \"listing\")"),
    LinkToCompany = paste0("=HYPERLINK(\"", LinkToCompany, "\", \"company\")")
  )

# create a workbook in memory from this data frame

header_style <- createStyle(textDecoration = "bold", halign = "center")

ws <- "Tracker"
wb <- createWorkbook()
addWorksheet(wb, ws)
writeData(wb,ws, df, headerStyle = header_style)
freezePane(wb, ws, firstRow = TRUE)

# the links into the workbook

writeFormula(wb, ws, startRow = 2, startCol = 7,
             x = df$LinkToCard
)
writeFormula(wb, ws, startRow = 2, startCol = 8,
             x = df$LinkToJob
)
writeFormula(wb, ws, startRow = 2, startCol = 9,
             x = df$LinkToCompany
)

# set up conditional formatting for the Status column

conditionalFormatting(wb, ws, cols=5, rows=2:nrow(df), type="expression",
                      rule='="Rejected"', style=createStyle(bgFill="red"))
conditionalFormatting(wb, ws, cols=5, rows=2:nrow(df), type="expression",
                      rule='="No Response"', style=createStyle(bgFill="orange"))
conditionalFormatting(wb, ws, cols=5, rows=2:nrow(df), type="expression",
                      rule='="Applied"', style=createStyle(bgFill="yellow"))
conditionalFormatting(wb, ws, cols=5, rows=2:nrow(df), type="expression",
                      rule='="Interview"', style=createStyle(bgFill="cyan"))
conditionalFormatting(wb, ws, cols=5, rows=2:nrow(df), type="expression",
                      rule='="Offer"', style=createStyle(bgFill="green"))
conditionalFormatting(wb, ws, cols=5, rows=2:nrow(df), type="expression",
                      rule='="Declined"', style=createStyle(bgFill="gray"))
conditionalFormatting(wb, ws, cols=5, rows=2:nrow(df), type="expression",
                      rule='="Accepted"', style=createStyle(fontColour="white", bgFill="black"))

# default the column width to auto and then make adjustments

setColWidths(wb, ws, cols=1:ncol(df), widths="auto")
setColWidths(wb, ws, cols=13, widths=15)
setColWidths(wb, ws, cols=c(3:6,12,14), widths=12)

# done
saveWorkbook(wb, paste0(options$board_to_use,".xlsx"), overwrite=TRUE)

# Save the_cards out in other formats -------------

saveRDS(the_cards, paste0(options$board_to_use,".rds"))
write_csv(the_cards,paste0(options$board_to_use,".csv"))
# create a reference CSV listing the column types for the main CSV
data.frame(Columns = colnames(the_cards), Types = sapply(the_cards, class)) %>% write_csv(paste0(options$board_to_use,"_coltypes.csv"))


