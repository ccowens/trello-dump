# trello-dump

This script demonstrates using the *trelloR* package to get useful information out of a Trello board and then collect it together in a table-like format. In this case, it's a board I use for job hunting.

## Data collected from Trello entry

Here's how I use some of the Trello features for job hunting and how they are mapped.

-   Each Trello card represents a single job opportunity

-   The Trello **title** is parsed as (*company*) *job* into these separate columns

- Each card can be in one of these Trello **lists** to represent its *status* in the job-hunt pipeline:

  -   Create/Prep

  -   Applied/Submitted

  -   Interview

  -   Rejected

  -   No Response

-   The Trello **label** is used to represent the *location type* for the job:

    -   On-site

    -   Hybrid

    -   Remote

-   The Trello date is used to create a completed **due date** that represents the initial *application date*

- The Trello **description** field is used to represent the following information as the first four lines:

  1.  Link: the job listing URL (usually on LinkedIn because it keeps expired listings)

  2.  Location:

  3.  Interview Date: next or last interview

  4.  Rejected Date: for explicit rejections not no responses

  *Location*, *interview date*, and *rejected* date all appear as columns

-   The remaining lines in the Trello **description** field are saved as an *other notes* field

-   The Trello **card ID** is used to construct the *created date* for the card

## Additional generated fields

The script also calculates some additional columns for the spreadsheet:

-   An applied week field based on the applied date

-   A link to the card in Trello based on a Trello-generated URL for the card

-   A link to the job based on the URL derived from the first line of the description field

-   A link to a search for the company 

## Output

The script creates two files:

- An Excel file
- An R RDS file

The Excel file can be used as a convenient activity overview or for further graphic or data processing. Likewise, the RDS file is an R-specific format that can be used for further processing.

