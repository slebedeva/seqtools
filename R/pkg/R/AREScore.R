#### source: https://github.com/lianos/seqtools/blob/master/R/pkg/R/AREScore.R
### thanks Steve! https://lianos.netlify.app/ ## check out his multiGSEA too

## An implementation of the algorithm to score ARE's as described here:
## http://arescore.dkfz.de/info.html
## http://www.plosgenetics.org/article/info%3Adoi%2F10.1371%2Fjournal.pgen.1002433

## Input is a DNA or RNAString(Set)

## OK it depends on more stuff from his pckage, try to just install it
#devtools::install_github("lianos/seqtools/R/pkg/")

#basal=1;overlapping=1.5;d1.3=.75;d4.6=0.4;d7.9=0.2;within.AU=0.3; aub.min.length=20; aub.p.to.start=0.8; aub.p.to.end=0.55
AREscore <- function(x, basal=1.0, overlapping=1.5, d1.3=0.75, d4.6=0.4,
                     d7.9=0.2, within.AU=0.3,
                     aub.min.length=20, aub.p.to.start=0.8, aub.p.to.end=0.55) {
  xtype <- match.arg(substr(class(x), 1, 3), c("DNA", "RNA"))
  if (xtype == "DNA") {
    pentamer <- "ATTTA"
    overmer <- "ATTTATTTA"
  } else {
    pentamer <- "AUUUA"
    overmer <- "AUUUAUUUA"
  }

  x <- as(x, sprintf("%sStringSet", xtype))

  pmatches <- vmatchPattern(pentamer, x)
  omatches <- vmatchPattern(overmer, x)

  basal.score <- elementNROWS(pmatches) * basal
  over.score <- elementNROWS(omatches) * overlapping

  no.cluster <- data.frame(d1.3=0, d4.6=0, d7.9=0)
  clust <- lapply(pmatches, function(m) {
    if (length(m) < 2) {
      return(no.cluster)
    }
    wg <- width(gaps(m))
    data.frame(d1.3=sum(wg <= 3), d4.6=sum(wg >= 4 & wg <= 6),
               d7.9=sum(wg >= 7 & wg <= 9))
  })
  clust <- do.call(rbind, clust)
  dscores <- clust$d1.3 * d1.3 + clust$d4.6 * d4.6 + clust$d7.9 * d7.9

  au.blocks <- identifyAUBlocks(x, aub.min.length, aub.p.to.start, aub.p.to.end)
  aub.score <- sum(countOverlaps(pmatches, au.blocks) * within.AU)

  score <- basal.score + over.score + dscores + aub.score

  ans <- DataFrame(score=score, n.pentamer=elementNROWS(pmatches),
                   n.overmer=elementNROWS(omatches), au.blocks=au.blocks,
                   n.au.blocks=elementNROWS(au.blocks))
  cbind(ans, DataFrame(clust))
}


##' In order to account for an AU-rich context, AREScore identifies AU-blocks as
##' regions that are generally rich in As and Us. It does so by sliding a window
##' whose size is defined by \code{min.length} NTs over the entire length
##' of the input sequence, one nucleotide at a time.
##'
##' For each window, the algorithm calculates percent AU, and if the AU
##' percentage is equal to or greater than the number specified in
##' \code{p.to.start}, it marks the position of the first nucleotide of that
##' window as the beginning of a new AU-block. The algorithm continues scanning
##' downstream until it discovers a window with AU percentage equal to or
##' smaller than \code{p.to.end} (their implementation looks like its only
##' smaller than!). The last nucleotide of this window is marked
##' as the last nucleotide of the AU-block.
#min.length=20;p.to.start=0.8; p.to.end=0.55
identifyAUBlocks <- function(x, min.length=20, p.to.start=0.8, p.to.end=0.55) {
  xtype <- match.arg(substr(class(x), 1, 3), c("DNA", "RNA"))
  stopifnot(isSingleNumber(min.length) && min.length >= 5 && min.length <= 50)
  stopifnot(isSingleNumber(p.to.start) && p.to.start >= 0.50 &&
            p.to.start <= 0.95)
  stopifnot(isSingleNumber(p.to.end) && p.to.end >= 0.20 && p.to.end <= 0.70)
  stopifnot(p.to.start > p.to.end)

  if (xtype == "DNA") {
    AU <- "AT"
  } else {
    AU <- "AU"
  }

  x <- as(x, sprintf("%sStringSet", xtype))
## apparently it cannot be applied to a stringset?
  au.freq <- lapply(x, function(y) letterFrequencyInSlidingView(y, min.length, AU, as.prob=TRUE))
  widths <- width(x)

  au.blocks <- lapply(1:length(x), function(i) {
    #print(names(x)[i])
    au <- au.freq[[i]]
    if (is.null(au)) {
      return(IRanges())
    }
    au <- as.numeric(au)

    can.start <- au >= p.to.start
    can.end <- au <= p.to.end

    ## posts <- .au.blocks(au, p.to.start, p.to.end)
    posts <- .Call("find_au_start_end", au, p.to.start, p.to.end,
                   PACKAGE="SeqTools")
    ## make sure to avoid empty blocks, not sure what this function above does
    posts <- posts[posts$start>0 & posts$end>0,]
    if (nrow(posts)<1) {
      return(IRanges())
    }
    blocks <- IRanges(posts$start, posts$end + min.length - 1L)
    end(blocks) <- ifelse(end(blocks) > widths[i], widths[i], end(blocks))
    reduce(blocks)
  })

  IRangesList(au.blocks)
}
