using System;

namespace MRSDistCompWebApp.Models
{
    public class ComputationInfo
    {
        public Guid Id { get; set; }

        public string ProjectName { get; set; }

        public string ProjectDesc { get; set; }

        public string Formula { get; set; }
        public string DataCatalog { get; set; }

        public string ComputationType { get; set; }

        public bool IsEnabled { get; set; }       
        
        public DateTime ValidFrom { get; set; }

        public DateTime ValidTo { get; set; }

        public Boolean Broadcast { get; set; }

    }
}
